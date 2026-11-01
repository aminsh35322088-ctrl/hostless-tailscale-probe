# Hostless Blue Knight + Tailscale Exit Node

A single Hostless App image that runs the Blue Knight Panel and a Tailscale userspace exit node together. Blue Knight owns the one public HTTP listener on Hostless `PORT`; `tailscaled` runs as a supervised background process with an in-memory ephemeral identity.

## Runtime requirements

Configure these **Hostless App secrets / environment variables** before deploying:

| Variable | Required | Purpose |
| --- | --- | --- |
| `TS_AUTHKEY` | Yes | Tailscale auth key or supported tagged OAuth client credential with permission to use `tag:exit` |
| `TS_HOSTNAME` | Yes | Unique DNS-label hostname for the ephemeral Tailscale node; no hostname is embedded in the source |
| `PANEL_PASSWORD` | Strongly recommended | Stable panel password (at least 8 characters) across container recreation |
| `UUID` | Strongly recommended | Stable V2Ray client UUID across container recreation |
| `SUB_TOKEN` | Strongly recommended | Stable subscription token across container recreation |
| `SS_PASSWORD` | Optional | Stable Shadowsocks password if that transport is enabled |

Do not commit credentials to Git. `TS_AUTHKEY` is never printed by the entrypoint. The Tailscale key must be allowed to apply `tag:exit`; device approval must also be satisfied when enabled in the tailnet.

## Storage model (no volume)

`BK_DATA_DIR` defaults to `/tmp/blue-knight-data`. Panel config, authentication material, generated certificates, engine binaries and traffic counters live in temporary container storage. They are lost when Hostless recreates the container. Supply the stable environment variables above to retain client-facing credentials and panel access; runtime-generated counters and other state will still reset. No Hostless volume is requested or required.

Tailscale runs with `--state=mem:`. The Tailscale node is ephemeral and is logged out on graceful shutdown. An abrupt container kill can leave an inactive ephemeral machine visible in the tailnet for a short period before Tailscale removes it.

## Hostless network constraints

Hostless Apps receive web traffic over HTTPS and forward it to the app's `PORT`. This deployment therefore uses Blue Knight's HTTP-compatible edge transports and intentionally disables UDP-only WireGuard, TUIC and Hysteria2 listeners. Do not enable them through environment overrides; Hostless's documented App runtime contract does not provide a public arbitrary-UDP port mapping.

The Tailscale daemon uses userspace (`netstack`) routing because this container does not have `/dev/net/tun` or `CAP_NET_ADMIN`. Userspace exit-node routing supports TCP and UDP by reconstructing connections, but it is not equivalent to kernel routing: arbitrary non-TCP/UDP IP protocols and end-to-end packet semantics are not preserved. Direct peer connectivity depends on actual UDP/NAT reachability and must be verified from another tailnet device; this image cannot guarantee Direct instead of DERP.

## Build and start

Hostless settings are described by `hostless.yaml`. It selects the Dockerfile, requires one successful HTTP check at `/knight/login`, and does not declare a volume. The container starts Tailscale first, then starts Blue Knight on the Hostless-provided `PORT`. If either child process exits, the supervisor stops the workload; on graceful shutdown it logs out the ephemeral Tailscale node.

The Blue Knight source snapshot and its upstream revision are documented in [`panel/UPSTREAM.md`](panel/UPSTREAM.md).

## Verification checklist after deployment

1. Confirm the Hostless deployment is healthy and `/knight/login` returns HTTP 200.
2. Confirm logs contain `TAILSCALE_JOIN_COMPLETE`, `BLUE_KNIGHT_PANEL_START`, and Blue Knight's `Public TCP multiplexer listening on 0.0.0.0:<PORT>` message.
3. Confirm the node appears in the tailnet with the configured hostname, `tag:exit`, ephemeral status, and advertised exit-node route.
4. Approve the exit-node route in the Tailscale admin console if required by the tailnet policy.
5. From a different device on the same tailnet, select the exit node and verify the public egress IP, DNS, TCP and UDP connectivity, then compare `tailscale ping` / `tailscale status` on Irancell and Hamrah Aval.
6. Import a Blue Knight subscription and test each generated HTTP-compatible protocol in a real client. The panel's own HTTP health check does not prove proxy transport success.

## Scope

This branch is an integration candidate, not a production deployment. No existing Hostless App settings or secrets are changed by building this repository branch.
