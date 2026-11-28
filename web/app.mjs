import {
  chains, demo, erc20, failureTopic, proxy, zero, word, calldata, quantity,
  addressOf, isAddress, chop, plan, parseUnits, units, defaultRescueLimit
} from "./chain.mjs";

const byId = id => document.getElementById(id);
const artifacts = await fetch("/contracts.json").then(response => response.json());
const provider = window.ethereum;
const form = byId("settings");
const trustedForm = byId("trusted-form");
const requestedTopic = "0x3fea28ae531038fe5468d875dfd4ed51df463364b27fabbcca924e59daa7af45";
const rescuedTopic = "0x974dd3ecadf080263a53c111f28f86729e9c6e326172cf64ede12b830ee21a71";
let wallet;
let state;
let sample = false;
let busy = false;
let paused = false;
let alertOnly = null;
let trustedResult;

async function rpc(chain, method, params = []) {
  const result = await fetch("/rpc/" + chain, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params })
  }).then(response => response.json());
  if (result.error) throw Error(result.error.message);
  return result.result;
}

const call = (chain, to, selector, ...args) => rpc(chain, "eth_call", [{ to, data: calldata(selector, ...args) }, "latest"]);
const guard = (item, name) => call("lasna", item.guard, artifacts.GuardReactive.methods[name + "()"]);
const guardian = (item, name) => call("sepolia", item.guardian, artifacts.RescueGuardian.methods[name + "()"]);
const key = account => "wallet-guard:v1:" + account;
const save = () => localStorage.setItem(key(wallet), JSON.stringify(state));
const message = text => { byId("message").textContent = text; };
const selected = () => sample ? demo : state;

function renderSetup() {
  const configured = Boolean(state);
  form.hidden = configured;
  byId("deployment").hidden = !configured;
  byId("prepare").disabled = !wallet || busy;
  byId("refresh").disabled = !selected()?.guardian || busy;
  byId("pause").disabled = busy;
  byId("mode").disabled = busy;
  byId("add-trusted").disabled = busy || trustedResult !== false;
  byId("remove-trusted").disabled = busy || trustedResult !== true;
  byId("connect").disabled = busy;
  byId("demo").disabled = busy;
  byId("account").textContent = wallet ? "已连接 " + chop(wallet) : "";
  if (!configured) return;
  const steps = plan(state, artifacts);
  byId("rule").textContent = "达到 " + state.threshold + " 时触发。救援只转往 " + state.vault +
    "，总额上限 " + state.cap + "，最多请求救援 " + (state.limit ?? defaultRescueLimit) +
    " 次。用完后自动退订。单独向钱包确认下面每一步。";
  byId("steps").replaceChildren(...steps.map(step => {
    const entry = document.createElement("li");
    const hash = state.transactions[step.key];
    entry.textContent = step.label + (hash ? " · " + (state.pending?.hash === hash ? "等待确认" : "已确认") : "");
    if (hash) entry.append(" ", link(chains[step.chain].scan + "/tx/" + hash, "交易"));
    return entry;
  }));
  byId("next").hidden = state.step >= steps.length;
  byId("next").disabled = busy;
  byId("next").textContent = state.pending ? "检查待确认交易" : steps[state.step]?.label || "";
  byId("change").hidden = state.step > 0 || !!state.pending;
  byId("change").disabled = busy;
}

function link(href, text) {
  const item = document.createElement("a");
  item.textContent = text;
  item.href = href;
  item.target = "_blank";
  item.rel = "noopener";
  return item;
}

function rows(values) {
  byId("status").replaceChildren(...values.map(([label, value]) => {
    const div = document.createElement("div");
    const title = document.createElement("dt");
    const data = document.createElement("dd");
    title.textContent = label;
    data.append(value);
    div.append(title, data);
    return div;
  }));
}

async function connect(accounts) {
  wallet = accounts[0]?.toLowerCase();
  sample = false;
  state = wallet ? JSON.parse(localStorage.getItem(key(wallet)) || "null") : null;
  trustedResult = undefined;
  byId("trusted-result").textContent = "";
  renderSetup();
  await refresh();
}

async function switchChain(chain) {
  const target = chains[chain];
  const request = (method, params = []) => provider.request({ method, params });
  const accounts = await request("eth_accounts");
  if (accounts[0]?.toLowerCase() !== wallet) throw Error("钱包账户已切换，请重新连接");
  try {
    await request("wallet_switchEthereumChain", [{ chainId: target.id }]);
  } catch (error) {
    if (error.code !== 4902) throw error;
    await request("wallet_addEthereumChain", [{
      chainId: target.id, chainName: target.name,
      nativeCurrency: { name: target.native, symbol: target.native, decimals: 18 },
      rpcUrls: [target.rpc], blockExplorerUrls: [target.scan]
    }]);
    await request("wallet_switchEthereumChain", [{ chainId: target.id }]);
  }
  if (BigInt(await request("eth_chainId")) !== BigInt(target.id)) throw Error("请切换到 " + target.name);
}

async function send(chain, transaction) {
  await switchChain(chain);
  return provider.request({ method: "eth_sendTransaction", params: [{ from: wallet, ...transaction }] });
}

async function receipt(chain, hash) {
  for (let i = 0; i < 14; i++) {
    const value = await rpc(chain, "eth_getTransactionReceipt", [hash]);
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 2000));
  }
  return null;
}

async function checkBinding(item) {
  const [bound, sender, targetProxy, token, account, vault, cap, totalCap] = await Promise.all([
    guard(item, "guardian"), guardian(item, "_CALLBACK_SENDER"), guardian(item, "_SERVICE_PROVIDER"),
    guardian(item, "TOKEN"), guardian(item, "PROTECTED"), guardian(item, "SAFE"),
    guardian(item, "MAX_PER_RESCUE"), guardian(item, "MAX_TOTAL")
  ]);
  return addressOf(bound) === item.guardian && addressOf(sender) === item.guard &&
    addressOf(targetProxy) === proxy && addressOf(token) === item.token && addressOf(account) === item.wallet &&
    addressOf(vault) === item.vault && BigInt(cap) === BigInt(totalCap) &&
    (!item.cap || BigInt(totalCap) === parseUnits(item.cap, item.decimals));
}

function enterSetup() {
  sample = false;
  renderSetup();
}

async function confirmStep() {
  enterSetup();
  const step = plan(state, artifacts)[state.step];
  if (!state.pending) {
    if (step.key === "approval" && !(await checkBinding(state))) throw Error("链上绑定或收款地址与配置不一致");
    const hash = await send(step.chain, step.transaction(state));
    state.transactions[step.key] = hash;
    state.pending = { hash };
    save();
    renderSetup();
  }
  const result = await receipt(step.chain, state.pending.hash);
  if (!result) {
    message("交易已发出。确认后点「检查待确认交易」继续。");
    return;
  }
  if (BigInt(result.status) !== 1n) {
    delete state.transactions[step.key];
    state.pending = null;
    save();
    throw Error("该笔交易失败，可以重试当前步骤");
  }
  if (step.key === "guard" || step.key === "guardian") {
    if (!isAddress(result.contractAddress)) throw Error("该笔交易未返回合约地址");
    state[step.key] = result.contractAddress.toLowerCase();
    if (step.key === "guardian") state.fromBlock = result.blockNumber;
    if (step.key === "guard") state.guardFromBlock = result.blockNumber;
  }
  state.step++;
  state.pending = null;
  save();
  message(state.step === 4 ? "配置交易全部确认。正在检查链上授权。" : "交易已确认，可以继续下一步。");
  await refresh();
}

function logRange(latest, start, blocks = 1000n) {
  const floor = BigInt(latest) > blocks ? BigInt(latest) - blocks : 0n;
  return quantity(BigInt(start || 0) > floor ? start : floor);
}

async function refreshHistory(item, decimals) {
  const latest = item.toBlock || await rpc("sepolia", "eth_blockNumber");
  const fromBlock = logRange(latest, item.fromBlock);
  const query = (address, topics) => rpc("sepolia", "eth_getLogs", [{ address, topics, fromBlock, toBlock: latest }]);
  const [success, failure] = await Promise.all([
    query(item.guardian, [rescuedTopic]), query(proxy, [failureTopic, "0x" + word(item.guardian)])
  ]);
  const events = [
    ...success.map(log => ({
      log, title: "已到账 " + units("0x" + log.data.slice(66, 130), decimals),
      source: log.topics[1], originIndex: log.data.slice(2, 66)
    })),
    ...failure.map(log => ({
      log, title: "回调失败", source: log.data.length >= 330 ? "0x" + log.data.slice(202, 266) : "",
      originIndex: log.data.length >= 330 ? log.data.slice(266, 330) : ""
    }))
  ].sort((a, b) => Number(BigInt(b.log.blockNumber) - BigInt(a.log.blockNumber)));
  const completed = new Set(events.map(entry => entry.source + entry.originIndex));
  byId("history-note").textContent = item.toBlock ? "显示 11 月 27 日演示区块的链上救援事件。" : "显示 Sepolia 最近 1,001 个区块内的链上救援事件。";
  if (item.guardFromBlock) {
    try {
      const head = item.guardToBlock || await rpc("lasna", "eth_blockNumber");
      const alertTopic = artifacts.GuardReactive.riskAlertTopic;
      const topics = alertTopic ? [[requestedTopic, alertTopic]] : [requestedTopic];
      const records = await rpc("lasna", "eth_getLogs", [{
        address: item.guard, topics,
        fromBlock: logRange(head, item.guardFromBlock), toBlock: head
      }]);
      for (const log of records.reverse()) {
        const source = log.topics[1];
        if (log.topics[0] === alertTopic) {
          const amount = units("0x" + log.data.slice(66, 130), decimals);
          const recipient = chop(addressOf(log.topics[2]));
          events.push({ log, title: "仅提醒 · 转出 " + amount + " 至 " + recipient, source, chain: "lasna" });
        } else if (!completed.has(source + log.data.slice(2, 66))) {
          events.push({ log, title: "已请求救援，待确认结果", source, chain: "lasna" });
        }
      }
    } catch {
      byId("history-note").textContent += " Lasna 请求记录暂不可用。";
    }
  }
  byId("history").replaceChildren(...events.slice(0, 15).map(({ log, title, source, chain = "sepolia" }) => {
    const li = document.createElement("li");
    li.append(title, " · ", link(chains[chain].scan + "/tx/" + log.transactionHash, "查看执行"));
    if (source) li.append(" · ", link(chains.sepolia.scan + "/tx/" + source, "触发转账"));
    return li;
  }));
  if (!events.length) byId("history-note").textContent += " 这段区块内没有救援记录。";
}

async function refresh() {
  const item = selected();
  byId("pause").hidden = true;
  byId("pause-note").hidden = true;
  byId("mode").hidden = true;
  byId("mode-note").hidden = true;
  byId("trusted").hidden = true;
  byId("history").replaceChildren();
  byId("history-note").textContent = "读取 Lasna 风险事件和 Sepolia 救援结果。";
  if (!item?.guardian) {
    rows([["当前状态", item ? "配置中" : "选择测试网案例或启用一份新保护。"]]);
    return;
  }
  rows([["当前状态", "正在读取链上数据…"]]);
  const [decimalsRaw, allowance, balance, pausedRaw, remaining, threshold, rescued, maxTotal, bound, mode] = await Promise.all([
    call("sepolia", item.token, erc20.decimals),
    call("sepolia", item.token, erc20.allowance, item.wallet, item.guardian),
    call("sepolia", item.token, erc20.balance, item.wallet),
    guard(item, "paused"), guard(item, "remaining"), guard(item, "threshold"),
    guardian(item, "totalRescued"), guardian(item, "MAX_TOTAL"), checkBinding(item),
    artifacts.GuardReactive.methods["alertOnly()"] && !sample ? guard(item, "alertOnly").catch(() => null) : null
  ]);
  const decimals = Number(BigInt(decimalsRaw));
  paused = BigInt(pausedRaw) !== 0n;
  alertOnly = mode == null ? null : BigInt(mode) !== 0n;
  let label = "已配置并授权";
  if (!bound) label = "待绑定";
  else if (BigInt(remaining) === 0n) label = "保护次数已用完";
  else if (paused) label = "已暂停";
  else if (alertOnly) label = "仅提醒";
  else if (BigInt(rescued) >= BigInt(maxTotal)) label = "保护额度已用完";
  else if (BigInt(allowance) === 0n) label = "待授权";
  else if (BigInt(balance) === 0n) label = "已配置并授权 · 钱包暂无该代币";
  rows([
    ["当前状态", label], ["受保护钱包", item.wallet], ["保险箱", item.vault],
    ["触发门槛", units(threshold, decimals)], ["钱包代币余额", units(balance, decimals)],
    ["链上剩余授权", units(allowance, decimals)], ["累计救援", units(rescued, decimals)],
    ["剩余触发次数", String(BigInt(remaining))], ["代币", link(chains.sepolia.scan + "/address/" + item.token, item.token)],
    ["测试网络", "Sepolia / Lasna"]
  ]);
  const canManage = !sample && bound && item.wallet === wallet && BigInt(remaining) > 0n;
  byId("pause").hidden = !canManage;
  byId("pause-note").hidden = !canManage;
  byId("trusted").hidden = !canManage || !artifacts.GuardReactive.methods["trustedRecipients(address)"];
  byId("pause").textContent = paused ? "恢复保护" : "暂停保护";
  byId("mode").hidden = !canManage || alertOnly === null;
  byId("mode-note").hidden = byId("mode").hidden;
  byId("mode").textContent = alertOnly ? "切换为自动救援" : "切换为仅提醒";
  await refreshHistory(item, decimals);
}

function run(action) {
  return async event => {
    event?.preventDefault();
    if (busy) return;
    busy = true;
    message("");
    renderSetup();
    try {
      await action();
    } catch (error) {
      message(error.code === 4001 ? "已取消钱包确认，可以再次尝试。" : error.message);
      if (byId("status").textContent.includes("正在读取链上数据")) rows([["当前状态", "读取失败，可点刷新重试。"]]);
    } finally {
      busy = false;
      renderSetup();
    }
  };
}

byId("connect").onclick = run(async () => {
  if (!provider) throw Error("请使用装有 MetaMask 等钱包扩展的浏览器打开本页。");
  await connect(await provider.request({ method: "eth_requestAccounts" }));
});
provider?.on?.("accountsChanged", run(async () => connect(await provider.request({ method: "eth_accounts" }))));
byId("demo").onclick = run(async () => { sample = true; await refresh(); });
byId("refresh").onclick = run(refresh);
byId("next").onclick = run(confirmStep);
byId("change").onclick = run(async () => { if (state.step === 0 && !state.pending) { state = null; localStorage.removeItem(key(wallet)); } });
byId("pause").onclick = run(async () => {
  const data = calldata(artifacts.GuardReactive.methods["setPaused(bool)"], paused ? 0 : 1);
  const hash = await send("lasna", { to: state.guard, data });
  const result = await receipt("lasna", hash);
  if (result && BigInt(result.status) !== 1n) throw Error("状态修改交易失败");
  if (!result) message("状态修改已提交，稍后刷新核对。交易编号 " + hash);
  await refresh();
});
byId("mode").onclick = run(async () => {
  if (sample || !state?.guard || alertOnly === null) throw Error("请先启用支持模式切换的新测试网合约");
  const data = calldata(artifacts.GuardReactive.methods["setAlertOnly(bool)"], alertOnly ? 0 : 1);
  const hash = await send("lasna", { to: state.guard, data });
  const result = await receipt("lasna", hash);
  if (result && BigInt(result.status) !== 1n) throw Error("模式切换交易失败");
  if (!result) message("切换已提交，稍后刷新核对。交易编号 " + hash);
  await refresh();
});
form.onsubmit = run(async () => {
  const input = Object.fromEntries(new FormData(form));
  const token = input.token.trim().toLowerCase();
  const vault = input.vault.trim().toLowerCase();
  if (!wallet || !isAddress(token) || !isAddress(vault) || token === zero || vault === zero || vault === wallet) {
    throw Error("请检查代币、钱包和保险箱地址");
  }
  const code = await rpc("sepolia", "eth_getCode", [token, "latest"]);
  if (code === "0x") throw Error("该地址在 Sepolia 上没有代币合约");
  const decimals = Number(BigInt(await call("sepolia", token, erc20.decimals)));
  await call("sepolia", token, erc20.balance, wallet);
  const next = { ...input, token, vault, decimals, wallet, step: 0, transactions: {} };
  plan(next, artifacts);
  state = next;
  save();
  enterSetup();
  message("配置检查通过。请核对保险箱和授权上限，再部署。");
});

function trustedAddress() {
  const address = new FormData(trustedForm).get("recipient").trim().toLowerCase();
  if (!isAddress(address) || address === zero) throw Error("请填写有效的收款地址");
  return address;
}

async function updateTrustedStatus(address) {
  const value = await call("lasna", state.guard, artifacts.GuardReactive.methods["trustedRecipients(address)"], address);
  if (address !== trustedAddress()) return;
  trustedResult = BigInt(value) !== 0n;
  byId("trusted-result").textContent = chop(address) + (trustedResult ? " 已设为可信，向它转出会跳过救援。" : " 当前按默认救援规则处理。");
}

async function changeTrusted(enabled) {
  if (sample || !state?.guard) throw Error("请先启用自己的测试网保护");
  const address = trustedAddress();
  const method = artifacts.GuardReactive.methods["setTrustedRecipient(address,bool)"];
  const hash = await send("lasna", { to: state.guard, data: calldata(method, address, enabled ? 1 : 0) });
  const result = await receipt("lasna", hash);
  if (result && BigInt(result.status) !== 1n) throw Error("常用地址更新失败");
  if (result) await updateTrustedStatus(address);
  else message("更新已提交。确认后可用「查链上状态」核对。交易编号 " + hash);
}

trustedForm.oninput = () => {
  trustedResult = undefined;
  byId("trusted-result").textContent = "";
  renderSetup();
};
trustedForm.onsubmit = run(async () => updateTrustedStatus(trustedAddress()));
byId("add-trusted").onclick = run(async () => changeTrusted(true));
byId("remove-trusted").onclick = run(async () => changeTrusted(false));
