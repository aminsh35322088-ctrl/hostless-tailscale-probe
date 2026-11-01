#!/bin/sh
set -eu
umask 077

TS_SOCKET="/tmp/tailscaled.sock"
TS_STATE_DIR="/data/tailscale"
TS_STATE="$TS_STATE_DIR/tailscaled.state"
TS_NODE_NAME="hostless-exit-1"
TS_PID=""
APP_PID=""

cleanup() {
  if [ -n "$APP_PID" ]; then kill -TERM "$APP_PID" 2>/dev/null || true; fi
  if [ -n "$TS_PID" ]; then kill -TERM "$TS_PID" 2>/dev/null || true; fi
  if [ -n "$APP_PID" ]; then wait "$APP_PID" 2>/dev/null || true; fi
  if [ -n "$TS_PID" ]; then wait "$TS_PID" 2>/dev/null || true; fi
}
trap cleanup INT TERM EXIT

# Do not create a disposable Tailnet identity. The Hostless volume must be
# mounted at /data so the same node key survives process restarts and deploys.
if ! awk '$5 == "/data" { found = 1 } END { exit(found ? 0 : 1) }' /proc/self/mountinfo; then
  echo "FATAL: PERSISTENT_VOLUME_NOT_MOUNTED at /data; refusing to authenticate with ephemeral state"
  exit 1
fi

if ! mkdir -p "$TS_STATE_DIR" || ! (umask 077; : > "$TS_STATE_DIR/.write-test-$$"); then
  echo "FATAL: PERSISTENT_STATE_PATH_NOT_WRITABLE: $TS_STATE_DIR"
  exit 1
fi
rm -f "$TS_STATE_DIR/.write-test-$$"

if [ -z "${TS_AUTHKEY:-}" ]; then
  echo "FATAL: TS_AUTHKEY is missing"
  exit 1
fi

if [ "${TS_HOSTNAME:-}" != "$TS_NODE_NAME" ]; then
  echo "NOTICE: enforcing unique Tailnet hostname $TS_NODE_NAME (TS_HOSTNAME is intentionally not allowed to create a duplicate)"
fi

echo "TAILSCALE_STATE_MODE=persistent PATH=$TS_STATE"
echo "HOSTLESS_TAILSCALE_USERSPACE_START"
tailscaled \
  --tun=userspace-networking \
  --state="$TS_STATE" \
  --socket="$TS_SOCKET" &
TS_PID=$!

ready=0
i=0
while [ "$i" -lt 30 ]; do
  if ! kill -0 "$TS_PID" 2>/dev/null; then
    echo "TAILSCALED_EXITED_EARLY"
    wait "$TS_PID" || true
    exit 1
  fi
  if [ -S "$TS_SOCKET" ]; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 1
done

if [ "$ready" -ne 1 ]; then
  echo "TAILSCALED_SOCKET_TIMEOUT"
  exit 1
fi

echo "TAILSCALE_DAEMON_READY"
tailscale version

# The reusable auth key is supplied only through Hostless runtime secrets.
# Keep the name and tag stable; persist the daemon state to reuse this device.
echo "TAILSCALE_JOIN_BEGIN hostname=$TS_NODE_NAME tag=tag:exit"
tailscale --socket="$TS_SOCKET" up \
  --auth-key="$TS_AUTHKEY" \
  --hostname="$TS_NODE_NAME" \
  --advertise-exit-node \
  --advertise-tags=tag:exit \
  --accept-dns=false \
  --accept-routes=false
echo "TAILSCALE_JOIN_COMPLETE"

echo "TAILSCALE_NETCHECK_BEGIN"
tailscale --socket="$TS_SOCKET" netcheck 2>&1 || true
echo "TAILSCALE_NETCHECK_END"

echo "TAILSCALE_STATUS_BEGIN"
tailscale --socket="$TS_SOCKET" status --json 2>&1 || true
echo "TAILSCALE_STATUS_END"

node /app/probe.js &
APP_PID=$!
wait "$APP_PID"
