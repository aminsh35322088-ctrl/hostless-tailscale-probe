#!/bin/sh
set -eu
umask 077

TS_SOCKET="/tmp/tailscaled.sock"
TS_PID=""
APP_PID=""

cleanup() {
  trap - EXIT INT TERM

  if [ -n "$APP_PID" ]; then
    kill -TERM "$APP_PID" 2>/dev/null || true
  fi

  if [ -n "$TS_PID" ] && kill -0 "$TS_PID" 2>/dev/null; then
    echo "TAILSCALE_EPHEMERAL_LOGOUT_BEGIN"
    tailscale --socket="$TS_SOCKET" logout >/dev/null 2>&1 || true
    kill -TERM "$TS_PID" 2>/dev/null || true
  fi

  if [ -n "$APP_PID" ]; then
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [ -n "$TS_PID" ]; then
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

# Accept a single DNS hostname label only; never substitute a baked-in name.
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

echo "TAILSCALE_STATE_MODE=ephemeral-memory no_volume_required"
echo "TAILSCALE_HOSTNAME_SOURCE=TS_HOSTNAME hostname=$TS_HOSTNAME"
echo "HOSTLESS_TAILSCALE_USERSPACE_START"

# mem: makes this an ephemeral Tailscale node without writing identity state to disk.
tailscaled \
  --tun=userspace-networking \
  --state=mem: \
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

# Credentials are read only from Hostless runtime secrets and never logged.
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

node /app/probe.js &
APP_PID=$!
wait "$APP_PID"
