#!/usr/bin/env bash
# 一键脚本：只在你自己的电脑上跑。签名用 Foundry 加密 keystore（--account camp），会提示输入 keystore 密码。
# 用法：
#   bash go.sh setup     # 下载依赖 + 本地测试（不用钱包、不花币）
#   bash go.sh check     # 看自己地址在 Sepolia / Lasna 的余额
#   bash go.sh swap      # （可选）用命令行把 0.02 Sepolia ETH 换成 2 lREACT；也可以在 MetaMask 里手动转
#   bash go.sh three     # 跨链回调三步走：部署 3 个合约 + 触发 + 打印 3 个交易链接
#   bash go.sh rescue    # 钱包救援演示：部署 + 假装被盗 + 打印 3 个交易链接
#   bash go.sh proof     # 再打印一遍所有证据链接
# 所有部署地址和交易哈希写在 deployments.env / PROOF.md（只有公开地址，没有私钥）。
set -euo pipefail
cd "$(dirname "$0")"

ACCOUNT="${ACCOUNT:-camp}"
SEPOLIA_RPC_URL="${SEPOLIA_RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
LASNA_RPC_URL="${LASNA_RPC_URL:-https://lasna-rpc.rnk.dev/}"
CALLBACK_PROXY="${CALLBACK_PROXY:-0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4}"
LREACT_FAUCET="0x9b9BB25f1A81078C544C829c5EB7822d747Cf434"
SEP_SCAN="${SEP_SCAN:-https://sepolia.etherscan.io}"
LASNA_SCAN="${LASNA_SCAN:-https://lasna.reactscan.net}"
STATE=deployments.env
export SEPOLIA_RPC_URL LASNA_RPC_URL CALLBACK_PROXY

touch "$STATE"
# shellcheck disable=SC1090
set -a; source "$STATE"; set +a

say()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }
save() { # save KEY VALUE
  grep -v "^$1=" "$STATE" > "$STATE.tmp" || true
  echo "$1=$2" >> "$STATE.tmp"; mv "$STATE.tmp" "$STATE"
  export "$1=$2"
}
need() { command -v "$1" >/dev/null 2>&1 || die "找不到 $1。先按 README.md 装好 Foundry，并执行 export PATH=\"\$HOME/.foundry/bin:\$PATH\""; }

need forge; need cast; need git

ensure_me() {
  if [ -n "${ME:-}" ]; then return; fi
  [ -f "$HOME/.foundry/keystores/$ACCOUNT" ] || [ -n "${FOUNDRY_KEYSTORES_DIR:-}" ] || \
    die "还没有 keystore「$ACCOUNT」。先运行：cast wallet import $ACCOUNT --interactive"
  say "读取你的测试钱包地址（需要输入一次 keystore 密码）"
  local a; a=$(cast wallet address --account "$ACCOUNT" | tail -1)
  [[ "$a" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "没读到地址：$a"
  save ME "$a"
  echo "你的测试地址：$ME"
}

# step <脚本文件:合约> <rpc> <要抓的变量名或 -> <交易记录键名>
step() {
  local target="$1" rpc="$2" var="$3" txkey="$4"
  local file="${target%%:*}"; file="${file##*/}"
  local chain; chain=$(cast chain-id --rpc-url "$rpc")
  say "运行 $target  (chainId $chain)"
  local log; log=$(mktemp)
  if ! forge script "$target" --rpc-url "$rpc" --broadcast --account "$ACCOUNT" --sender "$ME" 2>&1 | tee "$log"; then
    die "$target 失败。把上面红字截图（不要截到密码）发出来。"
  fi
  grep -q "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL" "$log" || die "$target 没有成功上链，看上面的报错。"
  if [ "$var" != "-" ]; then
    local addr; addr=$(grep -o "$var=0x[0-9a-fA-F]\{40\}" "$log" | tail -1 | cut -d= -f2)
    [ -n "$addr" ] || die "没抓到 $var"
    save "$var" "$addr"; echo "→ $var=$addr"
  fi
  local runf="broadcast/$file/$chain/run-latest.json"
  if [ -f "$runf" ]; then
    local h; h=$(grep -o '"hash": *"0x[0-9a-fA-F]\{64\}"' "$runf" | head -1 | grep -o '0x[0-9a-fA-F]\{64\}')
    [ -n "$h" ] && save "$txkey" "$h"
  fi
  rm -f "$log"
}

# 在 <rpc> 上等 <合约> 发出 <事件签名>，最多等 ~3 分钟，打印交易哈希
wait_log() {
  local rpc="$1" addr="$2" sig="$3" from="$4" i h=""
  local topic; topic=$(cast keccak "$sig")
  for i in $(seq 1 36); do
    h=$(cast logs --rpc-url "$rpc" --from-block "$from" --address "$addr" "$topic" 2>/dev/null \
        | awk '/transactionHash/ {print $2}' | tail -1)
    [ -n "$h" ] && { echo "$h"; return 0; }
    sleep 5
  done
  return 1
}

proof() {
  {
    echo "# 链上证据（自动生成，可直接贴进 README / WCB / DoraHacks）"
    echo
    echo "测试地址：${ME:-?}"
    echo
    echo "## 跨链回调三步走（Sepolia → Lasna → Sepolia）"
    echo "- CampOrigin（Sepolia）：${ORIGIN_ADDR:+$SEP_SCAN/address/$ORIGIN_ADDR}"
    echo "- CampReactive（Lasna）：${REACTIVE_ADDR:+$LASNA_SCAN/address/$REACTIVE_ADDR}"
    echo "- CampCallback（Sepolia）：${CALLBACK_ADDR:+$SEP_SCAN/address/$CALLBACK_ADDR}"
    echo "- ① 源链 Ping 交易：${TX3_PING:+$SEP_SCAN/tx/$TX3_PING}"
    echo "- ② Lasna react() 交易：${TX3_REACT:+$LASNA_SCAN/tx/$TX3_REACT}"
    echo "- ③ 目标链回调交易：${TX3_CALLBACK:+$SEP_SCAN/tx/$TX3_CALLBACK}"
    echo
    echo "## 钱包救援（跑通你的项目）"
    echo "- PracticeToken PRAC（Sepolia）：${TOKEN_ADDR:+$SEP_SCAN/address/$TOKEN_ADDR}"
    echo "- GuardReactive（Lasna）：${GUARD_ADDR:+$LASNA_SCAN/address/$GUARD_ADDR}"
    echo "- RescueGuardian（Sepolia）：${GUARDIAN_ADDR:+$SEP_SCAN/address/$GUARDIAN_ADDR}"
    echo "- 安全地址：${SAFE_ADDR:-}"
    echo "- ① 假装被盗交易：${TXR_THEFT:+$SEP_SCAN/tx/$TXR_THEFT}"
    echo "- ② Lasna 判断异常并请求救援：${TXR_REACT:+$LASNA_SCAN/tx/$TXR_REACT}"
    echo "- ③ Sepolia 救援回调（剩余币搬到安全地址）：${TXR_CALLBACK:+$SEP_SCAN/tx/$TXR_CALLBACK}"
  } > PROOF.md
  cat PROOF.md
}

cmd="${1:-help}"
case "$cmd" in
  setup)
    say "下载依赖（forge-std、reactive-lib-omni v0.1.0）"
    mkdir -p lib
    [ -d lib/forge-std/src ] || git clone --depth 1 --branch v1.17.0 https://github.com/foundry-rs/forge-std lib/forge-std
    [ -d lib/reactive-lib-omni/src ] || git clone --depth 1 --branch v0.1.0 https://github.com/Reactive-Network/reactive-lib-omni lib/reactive-lib-omni
    say "本地测试（不用钱包、不花币）"
    forge test
    ;;
  check)
    ensure_me
    say "余额"
    echo "Sepolia ETH : $(cast balance "$ME" --rpc-url "$SEPOLIA_RPC_URL" --ether)"
    echo "Lasna lREACT: $(cast balance "$ME" --rpc-url "$LASNA_RPC_URL" --ether)"
    echo "Sepolia 地址页：$SEP_SCAN/address/$ME"
    echo "Lasna 地址页（环境准备的持币证明）：$LASNA_SCAN/address/$ME"
    ;;
  swap)
    ensure_me
    amt="${2:-0.02ether}"
    say "把 $amt Sepolia ETH 转给官方 lREACT 水龙头 $LREACT_FAUCET（1 ETH → 100 lREACT）"
    cast send "$LREACT_FAUCET" --value "$amt" --rpc-url "$SEPOLIA_RPC_URL" --account "$ACCOUNT"
    echo "约 1 分钟后运行 bash go.sh check 看 Lasna 余额。"
    ;;
  three)
    ensure_me
    [ -n "${ORIGIN_ADDR:-}" ]   || step script/ThreeStep.s.sol:DeployOrigin   "$SEPOLIA_RPC_URL" ORIGIN_ADDR   TX3_ORIGIN_DEPLOY
    [ -n "${REACTIVE_ADDR:-}" ] || step script/ThreeStep.s.sol:DeployReactive "$LASNA_RPC_URL"   REACTIVE_ADDR TX3_REACTIVE_DEPLOY
    [ -n "${CALLBACK_ADDR:-}" ] || step script/ThreeStep.s.sol:DeployCallback "$SEPOLIA_RPC_URL" CALLBACK_ADDR TX3_CALLBACK_DEPLOY
    [ -n "${TX3_SETRECIPIENT:-}" ] || step script/ThreeStep.s.sol:SetRecipient "$LASNA_RPC_URL" - TX3_SETRECIPIENT
    if [ -z "${TX3_CALLBACK:-}" ]; then
      if [ -z "${TX3_PING:-}" ]; then
        save TX3_LASNA_FROM "$(cast block-number --rpc-url "$LASNA_RPC_URL")"
        save TX3_SEP_FROM "$(cast block-number --rpc-url "$SEPOLIA_RPC_URL")"
        step script/ThreeStep.s.sol:Ping "$SEPOLIA_RPC_URL" - TX3_PING
      fi
      lf="$TX3_LASNA_FROM"; sf="$TX3_SEP_FROM"
      say "等 Lasna 上的 react() …"
      h=$(wait_log "$LASNA_RPC_URL" "$REACTIVE_ADDR" "CallbackRequested(uint256,address,uint256)" "$lf") \
        || die "3 分钟没等到 react()。看 README.md 的「出问题怎么办」（多半是 lREACT 不够或订阅没匹配）。"
      save TX3_REACT "$h"
      say "等 Sepolia 上的回调 …"
      h=$(wait_log "$SEPOLIA_RPC_URL" "$CALLBACK_ADDR" "Handled(address,uint256,uint256,uint256,uint256)" "$sf") \
        || die "3 分钟没等到回调。看 README.md 的「出问题怎么办」（多半是回调合约没 ETH 或 Proxy 地址）。"
      save TX3_CALLBACK "$h"
    fi
    say "三步走完成 ✅"
    proof
    ;;
  rescue)
    ensure_me
    if [ -z "${SAFE_ADDR:-}" ]; then
      echo "安全地址 = 你 MetaMask 里第二个账户（Account 2）的地址，只收币，不用领测试币。"
      read -r -p "粘贴安全地址 0x...: " s
      [[ "$s" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "地址格式不对"
      [ "$(echo "$s" | tr 'A-F' 'a-f')" != "$(echo "$ME" | tr 'A-F' 'a-f')" ] || die "安全地址不能和测试地址相同"
      save SAFE_ADDR "$s"
    fi
    [ -n "${TOKEN_ADDR:-}" ]    || step script/Rescue.s.sol:DeployToken    "$SEPOLIA_RPC_URL" TOKEN_ADDR    TXR_TOKEN_DEPLOY
    [ -n "${GUARD_ADDR:-}" ]    || step script/Rescue.s.sol:DeployGuard    "$LASNA_RPC_URL"   GUARD_ADDR    TXR_GUARD_DEPLOY
    [ -n "${GUARDIAN_ADDR:-}" ] || step script/Rescue.s.sol:DeployGuardian "$SEPOLIA_RPC_URL" GUARDIAN_ADDR TXR_GUARDIAN_DEPLOY
    [ -n "${TXR_SETGUARDIAN:-}" ] || step script/Rescue.s.sol:SetGuardian  "$LASNA_RPC_URL"   -             TXR_SETGUARDIAN
    if [ -z "${TXR_CALLBACK:-}" ]; then
      if [ -z "${TXR_THEFT:-}" ]; then
        save TXR_LASNA_FROM "$(cast block-number --rpc-url "$LASNA_RPC_URL")"
        save TXR_SEP_FROM "$(cast block-number --rpc-url "$SEPOLIA_RPC_URL")"
        step script/Rescue.s.sol:FakeTheft "$SEPOLIA_RPC_URL" - TXR_THEFT
      fi
      lf="$TXR_LASNA_FROM"; sf="$TXR_SEP_FROM"
      say "等 Lasna 哨兵判断 …"
      h=$(wait_log "$LASNA_RPC_URL" "$GUARD_ADDR" "RescueRequested(uint256,uint256,uint256)" "$lf") \
        || die "3 分钟没等到哨兵触发。看 README.md 的「出问题怎么办」。"
      save TXR_REACT "$h"
      say "等 Sepolia 救援回调 …"
      h=$(wait_log "$SEPOLIA_RPC_URL" "$GUARDIAN_ADDR" "Rescued(uint256,uint256,uint256,uint256)" "$sf") \
        || die "3 分钟没等到救援回调。看 README.md 的「出问题怎么办」。"
      save TXR_CALLBACK "$h"
    fi
    say "PRAC 余额（单位 PRAC）"
    for who in "测试地址(被盗)=$ME" "安全地址=$SAFE_ADDR" "攻击者0xdEaD=0x000000000000000000000000000000000000dEaD"; do
      n="${who%%=*}"; a="${who#*=}"
      b=$(cast call "$TOKEN_ADDR" 'balanceOf(address)(uint256)' "$a" --rpc-url "$SEPOLIA_RPC_URL" | awk '{print $1}')
      echo "$n: $(cast from-wei "$b")"
    done
    say "钱包救援跑通 ✅"
    proof
    ;;
  proof) proof ;;
  *) sed -n '2,12p' "$0" ;;
esac
