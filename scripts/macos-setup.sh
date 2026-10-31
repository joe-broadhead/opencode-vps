#!/usr/bin/env bash
# macOS host: managed OpenCode service + Tailscale Serve.
#
#   ./scripts/macos-setup.sh
#   ./scripts/macos-setup.sh --port 49374
#   ./scripts/macos-setup.sh --no-serve
#
# The launch agent runs as the user you are logged in as. It survives reboot.
# Tailscale must already be connected. Without admin rights, install the CLI
# and run scripts/macos-userspace.sh first, then re-run this script.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"

usage() { sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

SKIP_OC=0
NO_SERVE=0
JSON=0
PORT="${OC_PORT:-$OC_PORT_DEFAULT}"

while [ $# -gt 0 ]; do
	case "$1" in
		--user)            OC_USER="${2:?}"; shift 2 ;;
		--user=*)          OC_USER="${1#*=}"; shift ;;
		--port)            PORT="${2:?}"; shift 2 ;;
		--port=*)          PORT="${1#*=}"; shift ;;
		--tailnet-key)     TS_AUTHKEY="${2:?}"; shift 2 ;;
		--tailnet-key=*)   TS_AUTHKEY="${1#*=}"; shift ;;
		--rotate-password) ROTATE_PASSWORD=1; shift ;;
		--skip-opencode)   SKIP_OC=1; shift ;;
		--no-serve)        NO_SERVE=1; shift ;;
		--json)            JSON=1; shift ;;
		-h|--help)         usage; exit 0 ;;
		*)                 die "unknown flag: $1 (try --help)" ;;
	esac
done

[ "$(uname -s)" = "Darwin" ] || die "scripts/macos-setup.sh is for macOS. On Linux run sudo ./scripts/setup.sh"

me="$(id -un)"
if [ -n "${OC_USER:-}" ] && [ "$OC_USER" != "$me" ]; then
	die "the macOS launch agent runs as ${me}. --user ${OC_USER} is not supported"
fi
export OC_USER="$me"
export OC_PORT="$PORT"
export ROTATE_PASSWORD="${ROTATE_PASSWORD:-0}"

if [ "$SKIP_OC" -eq 0 ]; then
	"$HERE/10-install-opencode.sh"
else
	log "skipping opencode install (--skip-opencode)"
fi

need_cmd opencode
need_cmd python3

if ! ts ip -4 >/dev/null 2>&1; then
	if [ -n "${TS_AUTHKEY:-}" ] && command -v tailscale >/dev/null 2>&1; then
		log "connecting to the tailnet with an auth key"
		ts up --auth-key "$TS_AUTHKEY" --hostname "$(hostname -s)" || true
	fi
fi
if ! ts ip -4 >/dev/null 2>&1; then
	warn "Tailscale is not connected."
	warn "  Install the Tailscale app, run: tailscale up"
	warn "  Or, without admin rights: ./scripts/macos-userspace.sh"
	warn "Then re-run ./scripts/macos-setup.sh"
	exit 2
fi
ok "tailscale connected: $(ts ip -4 | head -n1)"

dns="$(tailnet_dns)"
if [ -z "$dns" ]; then
	warn "no MagicDNS name. Enable MagicDNS and HTTPS Certificates, then re-run."
	exit 2
fi
ok "tailnet name: $dns"

created=0
pw="$(read_password || true)"
if [ -z "$pw" ] || [ "$ROTATE_PASSWORD" = "1" ]; then
	pw="$(gen_password)"
	created=1
	log "writing a new server password into the managed service config"
fi

# These stop a running managed server. The launch agent starts it again.
opencode service set hostname 127.0.0.1
opencode service set port "$PORT"
if [ "$created" -eq 1 ]; then
	opencode service set password "$pw"
fi

if port_in_use_by_other "$PORT"; then
	# The managed service may still be exiting. Stop it, then look again.
	opencode service stop >/dev/null 2>&1 || true
	sleep 1
fi
if port_in_use_by_other "$PORT"; then
	warn "port $PORT is still in use:"
	lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2 || true
	die "stop that process or re-run with --port"
fi

libdir="${HOME}/.local/lib/opencode-vps"
logdir="${HOME}/Library/Logs"
agentdir="${HOME}/Library/LaunchAgents"
mkdir -p "$libdir" "$logdir" "$agentdir"
install -m 755 "$REPO/launchd/serve.sh" "$libdir/serve.sh"

bin="$(command -v opencode)"
plist="${agentdir}/com.opencode.vps.plist"
python3 - "$REPO/launchd/opencode.plist.in" "$plist" "$libdir/serve.sh" "$HOME" "$bin" "$PORT" "$PATH" "$logdir/opencode-vps.log" <<'PY'
import pathlib, sys
src, dst, serve, home, bin_, port, path, log = sys.argv[1:]
def xml(value):
    return (value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
text = pathlib.Path(src).read_text()
repl = {
    "@OC_SERVE_SH@": serve,
    "@OC_HOME@": home,
    "@OC_BIN@": bin_,
    "@OC_PORT@": port,
    "@OC_PATH@": path,
    "@OC_LOG@": log,
}
for key, val in repl.items():
    text = text.replace(key, xml(val))
pathlib.Path(dst).write_text(text)
PY
chmod 644 "$plist"

uid="$(id -u)"
launchctl bootout "gui/${uid}/com.opencode.vps" 2>/dev/null || true
opencode service stop >/dev/null 2>&1 || true
launchctl bootstrap "gui/${uid}" "$plist"
launchctl enable "gui/${uid}/com.opencode.vps" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/${uid}/com.opencode.vps" >/dev/null 2>&1 || true

log "waiting for the API on 127.0.0.1:${PORT}"
up=0
for _ in $(seq 1 40); do
	pw="$(read_password || true)"
	if [ -n "$pw" ] && curl -fsS --max-time 2 -u "opencode:${pw}" "http://127.0.0.1:${PORT}/api/info" >/dev/null 2>&1; then
		up=1
		break
	fi
	sleep 1
done
[ "$up" -eq 1 ] || die "launch agent did not answer on 127.0.0.1:${PORT}. See ${logdir}/opencode-vps.log"
ok "service is up: http://127.0.0.1:${PORT}"

if [ "$NO_SERVE" -eq 1 ]; then
	log "skipping tailscale serve (--no-serve)"
else
	OC_PORT="$PORT" "$HERE/40-enable-serve.sh"
fi

echo
set +e
if [ "$JSON" -eq 1 ]; then
	OC_PORT="$PORT" "$HERE/verify.sh" --json
else
	OC_PORT="$PORT" "$HERE/verify.sh"
fi
verify_rc=$?
set -e

echo
if [ "$created" -eq 1 ]; then
	OC_PORT="$PORT" "$HERE/show-password.sh"
else
	printf 'URL       https://%s\n' "$dns"
	printf 'Username  opencode\n'
	printf 'Password  unchanged (scripts/show-password.sh)\n'
fi
cat <<EOF

Phone app (QR and pairing link; works once, expires in 5 minutes)
  ./scripts/pair.sh

Phone browser
  Open https://${dns} and sign in. Share -> Add to Home Screen.

Laptop
  ./laptop/install-macos.sh --url https://${dns}
  then: oc-remote
EOF
exit "$verify_rc"
