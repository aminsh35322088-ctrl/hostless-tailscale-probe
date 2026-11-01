#!/bin/sh
set -eu

TS_SOCKET="/tmp/tailscaled.sock"
TS_STATE_DIR="${TS_STATE_DIR:-/data/tailscale}"
TS_PID=""
APP_PID=""

cleanup() {
  if [ -n "$APP_PID" ]; then kill -TERM "$APP_PID" 2>/dev/null || true; fi
  if [ -n "$TS_PID" ]; then kill -TERM "$TS_PID" 2>/dev/null || true; fi
  if [ -n "$APP_PID" ]; then wait "$APP_PID" 2>/dev/null || true; fi
  if [ -n "$TS_PID" ]; then wait "$TS_PID" 2>/dev/null || true; fi
}
trap cleanup INT TERM EXIT

# Keep the Tailscale identity on Hostless' attached persistent volume.
# Until /data is mounted, gracefully fall back to /tmp and make that explicit.
if mkdir -p "$TS_STATE_DIR" 2>/dev/null &&
   (umask 077; : > "$TS_STATE_DIR/.write-test-$$") 2>/dev/null; then
  rm -f "$TS_STATE_DIR/.write-test-$$"
  TS_STATE="$TS_STATE_DIR/tailscaled.state"
  echo "TAILSCALE_STATE_MODE=persistent PATH=$TS_STATE"
else
  TS_STATE="/tmp/tailscaled.state"
  echo "WARNING: TAILSCALE_STATE_MODE=ephemeral-fallback; attach a writable persistent volume at /data"
fi

rm -f "$TS_SOCKET"

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
tailscale version || true

if [ "${TS_JOIN:-false}" = "true" ]; then
  if [ -z "${TS_AUTHKEY:-}" ]; then
    echo "TS_JOIN=true but TS_AUTHKEY is missing"
    exit 1
  fi

  set -- \
    --auth-key="$TS_AUTHKEY" \
    --hostname="${TS_HOSTNAME:-hostless-exit}" \
    --advertise-exit-node \
    --accept-dns=false

  if [ -n "${TS_ADVERTISE_TAGS:-}" ]; then
    set -- "$@" --advertise-tags="$TS_ADVERTISE_TAGS"
  fi

  echo "TAILSCALE_JOIN_BEGIN"
  tailscale --socket="$TS_SOCKET" up "$@"
  echo "TAILSCALE_JOIN_COMPLETE"
else
  echo "TAILSCALE_JOIN_SKIPPED (set TS_JOIN=true and TS_AUTHKEY in Hostless App environment to join)"
fi

echo "TAILSCALE_STATUS_BEGIN"
tailscale --socket="$TS_SOCKET" status --json 2>&1 || true
echo "TAILSCALE_STATUS_END"

node /app/probe.js &
APP_PID=$!
wait "$APP_PID"
