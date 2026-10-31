#!/usr/bin/env bash
# Wire this laptop to the remote OpenCode server.
#
#   ./laptop/install-macos.sh --url https://host.tailnet.ts.net
#   ./laptop/install-macos.sh --url ... --password '...'   (non-interactive)
#
# macOS stores the password in the login keychain. Linux falls back to
# ~/.config/opencode-vps/password (0600) unless secret-tool is present.
set -euo pipefail

URL=""
PW=""
PREFIX="${PREFIX:-$HOME/.local/bin}"

while [ $# -gt 0 ]; do
	case "$1" in
		--url) URL="${2:?}"; shift 2 ;;
		--url=*) URL="${1#*=}"; shift ;;
		--password) PW="${2:?}"; shift 2 ;;
		--password=*) PW="${1#*=}"; shift ;;
		-h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown flag: $1" >&2; exit 1 ;;
	esac
done

[ -n "$URL" ] || { printf 'Server URL: '; read -r URL; }
[ -n "$URL" ] || { echo "a URL is required" >&2; exit 1; }

if [ -z "$PW" ]; then
	printf 'Server password: '
	stty -echo 2>/dev/null || true
	read -r PW
	stty echo 2>/dev/null || true
	echo
fi
[ -n "$PW" ] || { echo "a password is required" >&2; exit 1; }

echo "==> checking $URL"
if ! curl -fsS -u "opencode:$PW" "$URL/api/info" >/dev/null; then
	echo "!! authentication failed. Check the URL (from the VPS: scripts/show-password.sh)" >&2
	exit 1
fi
echo " ok server reachable"

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/opencode-vps"
mkdir -p "$CONF" "$PREFIX"

printf '%s\n' "$URL" > "$CONF/url"

if command -v security >/dev/null 2>&1; then
	security add-generic-password -U -a "$USER" -s opencode-vps -w "$PW" >/dev/null
	echo " ok password stored in the login keychain"
elif command -v secret-tool >/dev/null 2>&1; then
	printf '%s' "$PW" | secret-tool store --label="OpenCode VPS" service opencode-vps
	echo " ok password stored in the secret service"
else
	( umask 077; printf '%s\n' "$PW" > "$CONF/password" )
	echo " ok password stored in $CONF/password (0600)"
fi

install -m 755 "$(cd "$(dirname "$0")" && pwd)/oc-remote" "$PREFIX/oc-remote"

case ":$PATH:" in
	*":$PREFIX:"*) ;;
	*) echo "!! $PREFIX is not on PATH; add: export PATH=\"$PREFIX:\$PATH\"" ;;
esac

if ! command -v opencode >/dev/null 2>&1; then
	echo "!! opencode is not installed locally; install it with:"
	echo "   curl -fsSL https://opencode.ai/v2/install | bash"
fi

echo
echo "done. try: oc-remote"
echo "web UI:   $URL"
