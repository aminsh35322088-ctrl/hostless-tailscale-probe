# Hostless Cloudflare Tunnel + Hiddify Core

This branch deploys a separate Hostless app. It does not change the existing
`hostless-tailscale-stable` service.

## Runtime

- Hiddify Core **v5.5.5**, official Linux amd64/musl release.
- Hiddify sing-box **1.15.0-alpha.13** (reported by the pinned binary).
- cloudflared **2026.10.7**.
- One dedicated Cloudflare Tunnel and hostname: `ws.janfada.cc.cd`.
- No persistent volume; credentials and the generated config remain in runtime
  environment variables and ephemeral storage.

## Inbounds and Cloudflare routes

| Profile | Protocol | Transport | Local listener |
|---|---|---|---:|
| VLESS-WS | VLESS | WebSocket + TLS at Cloudflare | 127.0.0.1:8081 |
| VMess-WS | VMess | WebSocket + TLS at Cloudflare | 127.0.0.1:8082 |
| Trojan-WS | Trojan | WebSocket + TLS at Cloudflare | 127.0.0.1:8083 |
| VLESS-XHTTP | VLESS | XHTTP packet-up + TLS at Cloudflare | 127.0.0.1:8084 |

Cloudflare Tunnel ingress uses path-based routing on the same hostname. The
subscription endpoint is served by the Hostless app at
`/sub/<SUBSCRIPTION_TOKEN>` and returns base64-encoded Hiddify share links.

## Runtime secrets

The Hostless app stores these as write-only environment variables:
- `CF_TUNNEL_TOKEN`, `CF_HOSTNAME`
- `VLESS_UUID`, `WS_PATH`
- `VMESS_UUID`, `VMESS_WS_PATH`
- `TROJAN_PASSWORD`, `TROJAN_WS_PATH`
- `XHTTP_PATH`, `SUBSCRIPTION_TOKEN`

Never commit tunnel credentials, UUIDs, passwords, subscription tokens, or
private WebSocket/XHTTP paths to this repository.

## Compatibility limits

This app intentionally publishes only transports that can use the HTTP-based
Cloudflare Tunnel ingress. WebSocket profiles are proxied as HTTP WebSocket
upgrades. XHTTP uses packet-up mode so upload is carried by ordinary HTTP
requests. Hysteria2, TUIC, mKCP, raw UDP, WireGuard and other UDP/native-TCP
listeners are not included in this Cloudflare subscription; core support for
a protocol does not make Cloudflare Tunnel transparently forward that protocol.

This is an edge-mediated Cloudflare route, not direct P2P and not a native
Tailscale DERP replacement. The previous VLESS WebSocket handshake test
returned HTTP 101, but a real client data-transfer test remains the acceptance
test for every profile.
