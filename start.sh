#!/bin/sh
set -eu

TS_SOCKET="/tmp/tailscaled.sock"
TS_STATE="/tmp/tailscaled.state"
TS_PID=""
APP_PID=""

cleanup() {
  if [ -n "$APP_PID" ]; then kill -TERM "$APP_PID" 2>/dev/null || true; fi
  if [ -n "$TS_PID" ]; then kill -TERM "$TS_PID" 2>/dev/null || true; fi
  if [ -n "$APP_PID" ]; then wait "$APP_PID" 2>/dev/null || true; fi
  if [ -n "$TS_PID" ]; then wait "$TS_PID" 2>/dev/null || true; fi
}
trap cleanup INT TERM EXIT

rm -f "$TS_SOCKET" "$TS_STATE"

echo "HOSTLESS_TAILSCALE_USERSpace_START"
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
echo "TAILSCALE_STATUS_BEGIN"
tailscale --socket="$TS_SOCKET" status --json 2>&1 || true
echo "TAILSCALE_STATUS_END"

node /app/probe.js &
APP_PID=$!
wait "$APP_PID"
