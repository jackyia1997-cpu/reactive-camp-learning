export const chains = {
  sepolia: { id: "0xaa36a7", name: "Sepolia", native: "ETH", rpc: "https://ethereum-sepolia-rpc.publicnode.com", scan: "https://sepolia.etherscan.io" },
  lasna: { id: "0x512577", name: "Reactive Lasna", native: "lREACT", rpc: "https://lasna-rpc.rnk.dev/", scan: "https://lasna.reactscan.net" }
};
export const proxy = "0xaa14d9cd0f788ca23d11805986c1d8bd035d23b4";
export const zero = "0x" + "0".repeat(40);
export const demo = {
  wallet: "0xbf619a46280d4d7536a0fe0c00035be82888b3a2",
  token: "0x978fe8c66dcc5288bd62ce340d110404f13f9ca5",
  vault: "0x21ea8efddec6536bf1f47b45a23a13d6864fb575",
  guard: "0x9630a56afa3cd9ea410064c442ec59f472bbff64",
  guardian: "0x842e030365aad60d021f4e20ed02ea55180e2066",
  fromBlock: "0xba81e0",
  toBlock: "0xba81f4",
  guardFromBlock: "0x8f00ff",
  guardToBlock: "0x8f00ff"
};
export const erc20 = { decimals: "313ce567", approve: "095ea7b3", allowance: "dd62ed3e", balance: "70a08231" };
export const failureTopic = "0xc8313f695443128e273f1edfcec40b94b7deea8dfbeafd0043290d6601d999db";
export const isAddress = value => typeof value === "string" && /^0x[0-9a-f]{40}$/i.test(value);
export const word = value => (typeof value === "string" && /^0x[0-9a-f]+$/i.test(value)
  ? value.slice(2) : BigInt(value).toString(16)).padStart(64, "0").toLowerCase();
export const calldata = (selector, ...args) => "0x" + selector + args.map(word).join("");
export const quantity = value => "0x" + BigInt(value).toString(16);
export const addressOf = result => "0x" + result.slice(-40).toLowerCase();
export const chop = address => address.slice(0, 6) + "…" + address.slice(-4);
export const defaultRescueLimit = 3;

export function parseUnits(value, decimals) {
  if (!/^\d+(\.\d+)?$/.test(value) || !Number.isInteger(decimals) || decimals < 0 || decimals > 36) {
    throw Error("请输入有效代币金额");
  }
  const [whole, fraction = ""] = value.split(".");
  if (fraction.length > decimals) throw Error("金额的小数位超过代币精度");
  const result = BigInt(whole + fraction.padEnd(decimals, "0"));
  if (result <= 0n || result >= 2n ** 256n) throw Error("金额超出支持范围");
  return result;
}

export function units(value, decimals) {
  const raw = BigInt(value).toString().padStart(decimals + 1, "0");
  if (!decimals) return raw;
  const fraction = raw.slice(-decimals).replace(/0+$/, "");
  return raw.slice(0, -decimals) + (fraction ? "." + fraction : "");
}

export function plan(config, artifacts) {
  const { wallet, vault, token, decimals } = config;
  if (![wallet, vault, token].every(value => isAddress(value) && value.toLowerCase() !== zero)
    || wallet.toLowerCase() === vault.toLowerCase()) throw Error("请填写有效且不同的钱包和保险箱地址");
  const threshold = parseUnits(config.threshold, decimals);
  const cap = parseUnits(config.cap, decimals);
  const limit = Number(config.limit ?? defaultRescueLimit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 5) throw Error("请选择 1 到 5 次救援");
  const guard = artifacts.GuardReactive;
  const guardian = artifacts.RescueGuardian;
  return [
    { key: "guard", chain: "lasna", label: "部署守护合约 · 0.3 lREACT 起", transaction: () => ({
      data: guard.bytecode + [chains.sepolia.id, token, wallet, vault, chains.sepolia.id, threshold, limit].map(word).join(""),
      value: quantity(300000000000000000n)
    }) },
    { key: "guardian", chain: "sepolia", label: "部署救援合约 · 0.005 Sepolia ETH 起", transaction: state => ({
      data: guardian.bytecode + [proxy, state.guard, token, wallet, vault, cap, cap].map(word).join(""),
      value: quantity(5000000000000000n)
    }) },
    { key: "binding", chain: "lasna", label: "绑定两份合约", transaction: state => ({
      to: state.guard, data: calldata(guard.methods["setGuardian(address)"], state.guardian)
    }) },
    { key: "approval", chain: "sepolia", label: "签署有限额度授权", transaction: state => ({
      to: token, data: calldata(erc20.approve, state.guardian, cap)
    }) }
  ];
}
