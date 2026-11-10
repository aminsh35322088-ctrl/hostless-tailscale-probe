#!/bin/sh
set -eu
umask 077

: "${CF_TUNNEL_TOKEN:?CF_TUNNEL_TOKEN is required}"
: "${CF_HOSTNAME:?CF_HOSTNAME is required}"
: "${VLESS_UUID:?VLESS_UUID is required}"
: "${WS_PATH:?WS_PATH is required}"

node /app/make-config.js
echo "HIDDIFY_CORE_VERSION_BEGIN"
hiddify-core version
echo "HIDDIFY_CORE_VERSION_END"
echo "CLOUDFLARED_VERSION_BEGIN"
cloudflared --version
echo "CLOUDFLARED_VERSION_END"

HIDDIFY_PID=""
CLOUDFLARED_PID=""
HEALTH_PID=""

shutdown() {
  trap - EXIT INT TERM
  for pid in "$HEALTH_PID" "$CLOUDFLARED_PID" "$HIDDIFY_PID"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  for pid in "$HEALTH_PID" "$CLOUDFLARED_PID" "$HIDDIFY_PID"; do
    if [ -n "$pid" ]; then
      wait "$pid" 2>/dev/null || true
    fi
  done
  echo "SHUTDOWN_COMPLETE"
}
trap shutdown EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

echo "HIDDIFY_START_BEGIN"
hiddify-core --disable-color srun -c /tmp/hiddify-config.json &
HIDDIFY_PID=$!

echo "CLOUDFLARED_TUNNEL_START_BEGIN hostname=$CF_HOSTNAME"
TUNNEL_TOKEN="$CF_TUNNEL_TOKEN" cloudflared tunnel --no-autoupdate run &
CLOUDFLARED_PID=$!

node /app/health.js &
HEALTH_PID=$!

echo "SERVICE_PROCESSES_STARTED"
while :; do
  if ! kill -0 "$HIDDIFY_PID" 2>/dev/null; then
    echo "FATAL: HIDDIFY_CORE_EXITED"
    wait "$HIDDIFY_PID" || true
    exit 1
  fi
  if ! kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
    echo "FATAL: CLOUDFLARED_EXITED"
    wait "$CLOUDFLARED_PID" || true
    exit 1
  fi
  if ! kill -0 "$HEALTH_PID" 2>/dev/null; then
    echo "FATAL: HEALTH_SERVER_EXITED"
    wait "$HEALTH_PID" || true
    exit 1
  fi
  sleep 3
done
