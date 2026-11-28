import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";

const port = Number(process.env.WALLET_GUARD_PORT || 8784);
const endpoints = {
  sepolia: "https://ethereum-sepolia-rpc.publicnode.com",
  lasna: "https://lasna-rpc.rnk.dev/"
};
const assets = {
  "/": ["index.html", "text/html"],
  "/app.mjs": ["app.mjs", "text/javascript"],
  "/chain.mjs": ["chain.mjs", "text/javascript"],
  "/contracts.json": ["contracts.json", "application/json"]
};
const permitted = new Set(["eth_call", "eth_getCode", "eth_getLogs", "eth_blockNumber", "eth_getTransactionReceipt"]);

createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, "http://localhost").pathname;
    if (request.method === "GET" && assets[pathname]) {
      const [file, type] = assets[pathname];
      response.writeHead(200, { "content-type": type + "; charset=utf-8" });
      return response.end(await readFile(new URL(file, import.meta.url)));
    }
    const url = endpoints[pathname.slice(5)];
    if (request.method !== "POST" || !pathname.startsWith("/rpc/") || !url) {
      response.writeHead(404);
      return response.end();
    }
    // The browser wallet signs and broadcasts. The local bridge only serves reads.
    const localHosts = ["localhost:" + port, "127.0.0.1:" + port];
    if (!localHosts.includes(request.headers.host) ||
      (request.headers.origin && !localHosts.some(host => request.headers.origin === "http://" + host))) {
      response.writeHead(403);
      return response.end();
    }
    let raw = "";
    for await (const chunk of request) {
      raw += chunk;
      if (raw.length > 16000) throw Error("Request too large");
    }
    const payload = JSON.parse(raw);
    if (!permitted.has(payload.method)) throw Error("Read method unavailable");
    const upstream = await fetch(url, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(15000)
    });
    response.writeHead(upstream.ok ? 200 : 502, { "content-type": "application/json" });
    response.end(await upstream.text());
  } catch (error) {
    if (!response.headersSent) response.writeHead(502, { "content-type": "application/json" });
    response.end(JSON.stringify({ error: { message: error.message } }));
  }
}).listen(port, "127.0.0.1", () => {
  const url = "http://127.0.0.1:" + port;
  console.log("Wallet Guard: " + url);
  if (process.argv.includes("--open") && process.platform === "win32") {
    const browser = spawn("rundll32.exe", ["url.dll,FileProtocolHandler", url], { stdio: "ignore", windowsHide: true });
    browser.on("error", error => console.error(error.message));
    browser.unref();
  }
});
