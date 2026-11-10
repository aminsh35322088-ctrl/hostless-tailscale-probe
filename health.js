const http = require("node:http");

const port = Number(process.env.PORT || 8000);
const subscriptionToken = process.env.SUBSCRIPTION_TOKEN || "";
const hostname = process.env.CF_HOSTNAME || "";
const vlessUuid = process.env.VLESS_UUID || "";
const vlessWsPath = process.env.WS_PATH || "";
const vmessUuid = process.env.VMESS_UUID || "";
const vmessWsPath = process.env.VMESS_WS_PATH || "";
const trojanPassword = process.env.TROJAN_PASSWORD || "";
const trojanWsPath = process.env.TROJAN_WS_PATH || "";
const xhttpPath = process.env.XHTTP_PATH || "";

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be a valid TCP port");
}

function encode(value) {
  return encodeURIComponent(value);
}

function buildSubscription() {
  const links = [];
  const vlessWs = "vless://" + vlessUuid + "@" + hostname + ":443"
    + "?encryption=none&security=tls&sni=" + encode(hostname)
    + "&type=ws&host=" + encode(hostname) + "&path=" + encode(vlessWsPath)
    + "#Hostless-CF-VLESS-WS";
  links.push(vlessWs);

  const vmessConfig = {
    v: "2",
    ps: "Hostless-CF-VMess-WS",
    add: hostname,
    port: "443",
    id: vmessUuid,
    aid: "0",
    scy: "auto",
    net: "ws",
    type: "none",
    host: hostname,
    path: vmessWsPath,
    tls: "tls",
    sni: hostname
  };
  links.push("vmess://" + Buffer.from(JSON.stringify(vmessConfig)).toString("base64"));

  const trojan = "trojan://" + encode(trojanPassword) + "@" + hostname + ":443"
    + "?security=tls&sni=" + encode(hostname)
    + "&type=ws&host=" + encode(hostname) + "&path=" + encode(trojanWsPath)
    + "#Hostless-CF-Trojan-WS";
  links.push(trojan);

  const vlessXhttp = "vless://" + vlessUuid + "@" + hostname + ":443"
    + "?encryption=none&security=tls&sni=" + encode(hostname)
    + "&type=xhttp&host=" + encode(hostname) + "&path=" + encode(xhttpPath)
    + "&mode=packet-up#Hostless-CF-VLESS-XHTTP";
  links.push(vlessXhttp);

  return Buffer.from(links.join("\n") + "\n", "utf8").toString("base64");
}

function validSubscriptionConfig() {
  return subscriptionToken && hostname && vlessUuid && vlessWsPath
    && vmessUuid && vmessWsPath && trojanPassword && trojanWsPath && xhttpPath;
}

const server = http.createServer((req, res) => {
  const requestUrl = new URL(req.url || "/", "http://localhost");

  if (req.method === "GET" && (requestUrl.pathname === "/" || requestUrl.pathname === "/healthz")) {
    res.writeHead(200, {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store"
    });
    res.end(JSON.stringify({
      status: "ok",
      service: "hostless-cloudflare-hiddify",
      core: "5.5.5",
      subscriptionReady: Boolean(validSubscriptionConfig())
    }));
    return;
  }

  if (req.method === "GET" && subscriptionToken
      && requestUrl.pathname === "/sub/" + subscriptionToken) {
    if (!validSubscriptionConfig()) {
      res.writeHead(503, { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" });
      res.end("subscription configuration unavailable");
      return;
    }
    res.writeHead(200, {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
      "profile-title": "Hostless CF Hiddify",
      "profile-update-interval": "12",
      "access-control-allow-origin": "*"
    });
    res.end(buildSubscription());
    return;
  }

  res.writeHead(404, { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" });
  res.end("not found");
});

server.listen(port, "0.0.0.0", () => {
  console.log(JSON.stringify({ marker: "HOSTLESS_HEALTH_READY", port, subscription: "enabled" }));
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
