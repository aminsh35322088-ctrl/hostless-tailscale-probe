# Upstream source

This directory contains the Blue Knight Panel Hostless application snapshot reviewed for this integration.

- Upstream repository: https://github.com/BlueKnightNet/Blue-Knight-Panel-Hostless
- Upstream branch: `blue-knight-net`
- Upstream commit: `440dfdf59659b268d7516e2cde58363a9b673608`
- Upstream `package.json` declares MIT and names Blue Knight Net as the author. The corresponding notice is included in [`LICENSE`](LICENSE). The application source is kept under `panel/` so the Tailscale container entrypoint can supervise it without replacing its internal panel or proxy logic.
