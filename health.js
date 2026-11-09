const http = require("node:http");

const port = Number(process.env.PORT || 8000);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be a valid TCP port");
}

const server = http.createServer((req, res) => {
  if (req.url === "/" || req.url === "/healthz") {
    res.writeHead(200, {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store"
    });
    res.end(JSON.stringify({ status: "ok", service: "hostless-cloudflare-hiddify" }));
    return;
  }
  res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
  res.end("not found");
});

server.listen(port, "0.0.0.0", () => {
  console.log(JSON.stringify({ marker: "HOSTLESS_HEALTH_READY", port }));
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
