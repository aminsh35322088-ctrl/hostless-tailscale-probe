# Hostless Cloudflare Tunnel + Hiddify Core

This branch is a separate Hostless app. It does not change the existing
`hostless-tailscale-stable` service.

## Runtime design

- Hiddify Core v5.0.3 serves one VLESS + WebSocket inbound on
  `127.0.0.1:8081`.
- cloudflared connects outbound to a separately managed Cloudflare Tunnel.
- The Cloudflare public hostname routes to `http://127.0.0.1:8081`.
- Hostless health checks use a small HTTP endpoint on `$PORT` (default 8000).
- No persistent volume is needed. Credentials and the generated Hiddify
  configuration live only in runtime environment variables and ephemeral
  storage.

## Required runtime environment variables

Set these as write-only Hostless secrets:

- `CF_TUNNEL_TOKEN`: token for this app's dedicated Cloudflare Tunnel.
- `CF_HOSTNAME`: public hostname configured on that tunnel.
- `VLESS_UUID`: VLESS user UUID.
- `WS_PATH`: a long, unguessable WebSocket path beginning with `/`.

Never commit tunnel tokens, UUIDs, or WebSocket paths to this repository.

## Client profile

Use VLESS over WebSocket with TLS enabled:
- address: `CF_HOSTNAME`
- port: `443`
- transport: `ws`
- WebSocket path: `WS_PATH`
- TLS server name: same as `CF_HOSTNAME`
- encryption: `none`
- flow: empty

## Limitations

Cloudflare Tunnel is an edge-mediated path, not a direct P2P connection or a
replacement for Tailscale's native DERP protocol. This branch is intended to
test a Cloudflare-fronted VLESS/WebSocket access path. UDP-based protocols
such as TUIC and Hysteria2 are not provided by this WebSocket inbound.
