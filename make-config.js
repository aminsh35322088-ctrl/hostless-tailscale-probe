const fs = require("node:fs");

const env = process.env;
const hostname = env.CF_HOSTNAME || "";
const vlessUuid = env.VLESS_UUID || "";
const vlessWsPath = env.WS_PATH || "";
const vmessUuid = env.VMESS_UUID || "";
const vmessWsPath = env.VMESS_WS_PATH || "";
const trojanPassword = env.TROJAN_PASSWORD || "";
const trojanWsPath = env.TROJAN_WS_PATH || "";
const xhttpPath = env.XHTTP_PATH || "";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const pathPattern = /^\/[A-Za-z0-9_-]{20,96}$/;
const hostPattern = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/i;

if (!hostPattern.test(hostname)) throw new Error("CF_HOSTNAME must be a valid hostname");
if (!uuidPattern.test(vlessUuid)) throw new Error("VLESS_UUID must be a valid UUID");
if (!uuidPattern.test(vmessUuid)) throw new Error("VMESS_UUID must be a valid UUID");
if (!pathPattern.test(vlessWsPath)) throw new Error("WS_PATH must be a 20-96 character URL path");
if (!pathPattern.test(vmessWsPath)) throw new Error("VMESS_WS_PATH must be a 20-96 character URL path");
if (!pathPattern.test(trojanWsPath)) throw new Error("TROJAN_WS_PATH must be a 20-96 character URL path");
if (!pathPattern.test(xhttpPath)) throw new Error("XHTTP_PATH must be a 20-96 character URL path");
if (trojanPassword.length < 32) throw new Error("TROJAN_PASSWORD must be at least 32 characters");

const config = {
  log: { level: "info", timestamp: true },
  inbounds: [
    {
      type: "vless",
      tag: "vless-ws-in",
      listen: "127.0.0.1",
      listen_port: 8081,
      users: [{ uuid: vlessUuid }],
      transport: { type: "ws", path: vlessWsPath }
    },
    {
      type: "vmess",
      tag: "vmess-ws-in",
      listen: "127.0.0.1",
      listen_port: 8082,
      users: [{ uuid: vmessUuid }],
      transport: { type: "ws", path: vmessWsPath }
    },
    {
      type: "trojan",
      tag: "trojan-ws-in",
      listen: "127.0.0.1",
      listen_port: 8083,
      users: [{ password: trojanPassword }],
      transport: { type: "ws", path: trojanWsPath }
    },
    {
      type: "vless",
      tag: "vless-xhttp-in",
      listen: "127.0.0.1",
      listen_port: 8084,
      users: [{ uuid: vlessUuid }],
      transport: { type: "xhttp", path: xhttpPath, mode: "packet-up" }
    }
  ],
  outbounds: [{ type: "direct", tag: "direct" }]
};

fs.writeFileSync("/tmp/hiddify-config.json", JSON.stringify(config), { mode: 0o600 });
console.log(JSON.stringify({
  marker: "HIDDIFY_CONFIG_READY",
  coreTarget: "5.5.5",
  inbounds: [
    "VLESS-WS:8081",
    "VMess-WS:8082",
    "Trojan-WS:8083",
    "VLESS-XHTTP-packet-up:8084"
  ],
  secretsLoaded: true
}));
