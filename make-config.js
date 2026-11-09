const fs = require("node:fs");

const uuid = process.env.VLESS_UUID || "";
const wsPath = process.env.WS_PATH || "";
const hostname = process.env.CF_HOSTNAME || "";

if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(uuid)) {
  throw new Error("VLESS_UUID must be a valid UUID");
}
if (!/^\/[A-Za-z0-9._~-]{16,96}$/.test(wsPath)) {
  throw new Error("WS_PATH must be a 16-96 character URL path");
}
if (!/^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/i.test(hostname)) {
  throw new Error("CF_HOSTNAME must be a valid hostname");
}

const config = {
  log: { level: "info", timestamp: true },
  inbounds: [{
    type: "vless",
    tag: "vless-ws-in",
    listen: "127.0.0.1",
    listen_port: 8081,
    users: [{ uuid }],
    transport: { type: "ws", path: wsPath }
  }],
  outbounds: [{ type: "direct", tag: "direct" }]
};

fs.writeFileSync("/tmp/hiddify-config.json", JSON.stringify(config), { mode: 0o600 });
console.log(JSON.stringify({
  marker: "HIDDIFY_CONFIG_READY",
  inbound: "vless+ws",
  listen: "127.0.0.1:8081",
  hostname,
  pathLength: wsPath.length
}));
