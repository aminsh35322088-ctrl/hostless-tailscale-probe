const http = require("node:http");
const fs = require("node:fs");
const os = require("node:os");

function read(path) {
  try { return fs.readFileSync(path, "utf8").trim(); }
  catch (error) { return null; }
}

function inspectTun() {
  try {
    const s = fs.statSync("/dev/net/tun");
    return {
      exists: true,
      characterDevice: s.isCharacterDevice(),
      readable: (() => { try { fs.accessSync("/dev/net/tun", fs.constants.R_OK); return true; } catch { return false; } })(),
      writable: (() => { try { fs.accessSync("/dev/net/tun", fs.constants.W_OK); return true; } catch { return false; } })(),
      major: (s.rdev >> 8) & 0xfff,
      minor: (s.rdev & 0xff) | ((s.rdev >> 12) & 0xfff00),
    };
  } catch (error) {
    return { exists: false, error: error.code || error.message };
  }
}

function inspectCapabilities() {
  const status = read("/proc/self/status") || "";
  const capEff = status.match(/^CapEff:\\s*([0-9a-f]+)$/im)?.[1] || null;
  let capNetAdmin = false;
  if (capEff) {
    try { capNetAdmin = (BigInt("0x" + capEff) & (1n << 12n)) !== 0n; }
    catch {}
  }
  return { effectiveHex: capEff, capNetAdmin };
}

const report = {
  marker: "HOSTLESS_RUNTIME_PROBE",
  timestamp: new Date().toISOString(),
  process: { uid: typeof process.getuid === "function" ? process.getuid() : null, gid: typeof process.getgid === "function" ? process.getgid() : null },
  kernel: { release: os.release(), platform: os.platform(), architecture: os.arch() },
  tun: inspectTun(),
  capabilities: inspectCapabilities(),
  forwarding: {
    ipv4: read("/proc/sys/net/ipv4/ip_forward"),
    ipv6All: read("/proc/sys/net/ipv6/conf/all/forwarding"),
    ipv6Default: read("/proc/sys/net/ipv6/conf/default/forwarding")
  },
  proc: {
    routeTableReadable: read("/proc/net/route") !== null,
    ipv6RouteTableReadable: read("/proc/net/ipv6_route") !== null
  }
};

console.log("HOSTLESS_RUNTIME_PROBE_BEGIN");
console.log(JSON.stringify(report));
console.log("HOSTLESS_RUNTIME_PROBE_END");

const port = Number(process.env.PORT || 8080);
http.createServer((req, res) => {
  res.writeHead(200, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify({ status: "ok", service: "hostless-tailscale-probe" }));
}).listen(port, "0.0.0.0", () => {
  console.log(JSON.stringify({ marker: "HTTP_READY", port, host: "0.0.0.0" }));
});
