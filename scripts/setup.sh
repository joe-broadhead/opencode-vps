#!/usr/bin/env bash
# Orchestrator: one command from a fresh VPS to a working tailnet endpoint.
#
#   sudo ./scripts/setup.sh --user joe
#   sudo ./scripts/setup.sh --user joe --tailnet-key tskey-auth-...
#
# Flags:
#   --user NAME           account that runs the server (default: invoking user)
#   --port N              server port (default 49374)
#   --tailnet-key KEY     Tailscale auth key for unattended join (or TS_AUTHKEY)
#   --rotate-password     generate a new password (logs out all web sessions)
#   --skip-opencode       do not install/upgrade the CLI
#   --no-serve            stop after the systemd service (defer Tailscale)
#   --json                pass --json to the final verification
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

if [ "$(uname -s)" = "Darwin" ]; then
	log "macOS has no systemd; continuing with scripts/macos-setup.sh"
	exec "$HERE/macos-setup.sh" "$@"
fi

usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

SKIP_OC=0
NO_SERVE=0
JSON_ARGS=()

while [ $# -gt 0 ]; do
	case "$1" in
		--user)            OC_USER="${2:?}"; shift 2 ;;
		--user=*)          OC_USER="${1#*=}"; shift ;;
		--port)            OC_PORT="${2:?}"; shift 2 ;;
		--port=*)          OC_PORT="${1#*=}"; shift ;;
		--tailnet-key)     TS_AUTHKEY="${2:?}"; shift 2 ;;
		--tailnet-key=*)   TS_AUTHKEY="${1#*=}"; shift ;;
		--rotate-password) ROTATE_PASSWORD=1; shift ;;
		--skip-opencode)   SKIP_OC=1; shift ;;
		--no-serve)        NO_SERVE=1; shift ;;
		--json)            JSON_ARGS+=(--json); shift ;;
		-h|--help)         usage; exit 0 ;;
		*)                 die "unknown flag: $1 (try --help)" ;;
	esac
done

export OC_USER="${OC_USER:-$(target_user)}"
export OC_PORT="${OC_PORT:-$OC_PORT_DEFAULT}"
export TS_AUTHKEY="${TS_AUTHKEY:-}"
export ROTATE_PASSWORD="${ROTATE_PASSWORD:-0}"

if ! is_root; then
	log "this will use sudo for system changes"
	sudo -v || die "sudo is required"
fi

log "user=$OC_USER port=$OC_PORT host=$(hostname -s)"

if [ "$SKIP_OC" -eq 0 ]; then
	"$HERE/10-install-opencode.sh" || exit $?
else
	log "skipping opencode install (--skip-opencode)"
fi

set +e
"$HERE/20-install-tailscale.sh"
ts_rc=$?
set -e
if [ "$ts_rc" -ne 0 ]; then
	if [ "$ts_rc" -eq 2 ]; then
		warn "Tailscale needs the human step above. Once done, re-run:"
		warn "  sudo $0 --user $OC_USER --port $OC_PORT --skip-opencode"
	fi
	exit "$ts_rc"
fi

"$HERE/30-install-service.sh" || exit $?

if [ "$NO_SERVE" -eq 1 ]; then
	log "skipping tailscale serve (--no-serve) and final verification"
	PW="$(read_password)"
	printf '\nServer (loopback only): http://127.0.0.1:%s\nPassword: %s\n' "$OC_PORT" "$PW"
	exit 0
fi

set +e
"$HERE/40-enable-serve.sh"
serve_rc=$?
set -e
[ "$serve_rc" -eq 0 ] || exit "$serve_rc"

echo
"$HERE/verify.sh" "${JSON_ARGS[@]}"

DNS="$(tailnet_dns)"
PW="$(read_password)"
printf '\n%s\n' "-----------------------------------------------------------"
printf '  URL       https://%s\n' "$DNS"
printf '  Password  %s\n' "$PW"
printf '  Username  opencode   (only the password matters)\n'
printf '%s\n' "-----------------------------------------------------------"
cat <<EOF

Phone (OpenCode app — QR / pairing link, works once, expires in 5 minutes)
  ./scripts/pair.sh

Phone (mobile browser)
  1. Install Tailscale, sign in to the same tailnet.
  2. Open https://$DNS and authenticate (cookie lasts 30 days).
  3. Share -> Add to Home Screen.

Laptop
  ./laptop/install-macos.sh --url https://$DNS
  (it prompts for the password; do not put the password in the command)
  then: oc-remote
EOF
