#!/bin/sh
set -eu
umask 077

TS_SOCKET="/tmp/tailscaled.sock"
TS_PID=""
APP_PID=""
TS_FAILED=0

process_running() {
  pid="$1"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  state="$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null || true)"
  case "$state" in Z|X) return 1 ;; esac
  return 0
}

cleanup() {
  trap - EXIT INT TERM

  if process_running "$APP_PID"; then
    kill -TERM "$APP_PID" 2>/dev/null || true
  fi
  if [ -n "$APP_PID" ]; then
    wait "$APP_PID" 2>/dev/null || true
  fi

  if process_running "$TS_PID"; then
    echo "TAILSCALE_EPHEMERAL_LOGOUT_BEGIN"
    tailscale --socket="$TS_SOCKET" logout >/dev/null 2>&1 || true
    kill -TERM "$TS_PID" 2>/dev/null || true
    wait "$TS_PID" 2>/dev/null || true
  fi

  echo "SHUTDOWN_COMPLETE"
}
trap cleanup EXIT
trap 'exit 0' INT TERM

if [ -z "${TS_AUTHKEY:-}" ]; then
  echo "FATAL: TS_AUTHKEY is missing"
  exit 1
fi

if [ -z "${TS_HOSTNAME:-}" ]; then
  echo "FATAL: TS_HOSTNAME is missing"
  exit 1
fi

case "$TS_HOSTNAME" in
  *[!A-Za-z0-9-]*|-*|*-)
    echo "FATAL: TS_HOSTNAME must be a DNS hostname label (letters, digits and hyphens; no leading/trailing hyphen)"
    exit 1
    ;;
esac

TS_HOSTNAME_LENGTH=$(printf '%s' "$TS_HOSTNAME" | wc -c | tr -d '[:space:]')
if [ "$TS_HOSTNAME_LENGTH" -gt 63 ]; then
  echo "FATAL: TS_HOSTNAME exceeds 63 characters"
  exit 1
fi

# The panel is intentionally configured for ephemeral scratch storage; no Hostless volume is required.
BK_DATA_DIR="${BK_DATA_DIR:-/tmp/blue-knight-data}"
export BK_DATA_DIR
mkdir -p "$BK_DATA_DIR"
if [ ! -w "$BK_DATA_DIR" ]; then
  echo "FATAL: BK_DATA_DIR is not writable"
  exit 1
fi

# Hostless exposes the App as HTTPS web traffic, not arbitrary public UDP listeners.
# Keep UDP-only panel transports disabled so the UI never publishes unusable endpoints.
ENABLE_WIREGUARD=false
ENABLE_TUIC=false
ENABLE_HYSTERIA2=false
export ENABLE_WIREGUARD ENABLE_TUIC ENABLE_HYSTERIA2

echo "PANEL_STORAGE_MODE=ephemeral-scratch path=$BK_DATA_DIR no_volume_required"
echo "TAILSCALE_STATE_MODE=ephemeral-memory no_volume_required"
echo "TAILSCALE_HOSTNAME_SOURCE=TS_HOSTNAME hostname=$TS_HOSTNAME"
echo "HOSTLESS_TAILSCALE_USERSPACE_START"

tailscaled \
  --tun=userspace-networking \
  --state=mem: \
  --socket="$TS_SOCKET" &
TS_PID=$!

ready=0
i=0
while [ "$i" -lt 30 ]; do
  if ! process_running "$TS_PID"; then
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

echo "TAILSCALE_JOIN_BEGIN hostname=$TS_HOSTNAME tag=tag:exit"
tailscale --socket="$TS_SOCKET" up \
  --auth-key="$TS_AUTHKEY" \
  --hostname="$TS_HOSTNAME" \
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

echo "BLUE_KNIGHT_PANEL_START"
node /app/panel/index.js &
APP_PID=$!

# Keep the web app and Tailscale daemon as one supervised workload.
while process_running "$APP_PID"; do
  if ! process_running "$TS_PID"; then
    echo "FATAL: tailscaled exited while Blue Knight was running"
    TS_FAILED=1
    kill -TERM "$APP_PID" 2>/dev/null || true
    break
  fi
  sleep 5
done

if wait "$APP_PID"; then
  APP_STATUS=0
else
  APP_STATUS=$?
fi
if [ "$TS_FAILED" -eq 1 ]; then
  exit 1
fi
exit "$APP_STATUS"
