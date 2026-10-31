#!/usr/bin/env bash
# Shared helpers for the OpenCode VPS setup scripts. Sourced, never executed.
#
# Linux uses systemd and getent. macOS uses launchd and dscl. docker/ is the
# escape hatch when neither supervisor fits.

set -euo pipefail

OC_PORT_DEFAULT="${OC_PORT_DEFAULT:-49374}"
OC_CONF_DIR="${OC_CONF_DIR:-/etc/opencode}"
OC_ENV_FILE="${OC_ENV_FILE:-/etc/opencode/env}"
OC_UNIT_PATH="${OC_UNIT_PATH:-/etc/systemd/system/opencode.service}"

if [ -t 1 ]; then
	C_RESET=$'\033[0m'
	C_BLUE=$'\033[1;34m'
	C_GREEN=$'\033[1;32m'
	C_YELLOW=$'\033[1;33m'
	C_RED=$'\033[1;31m'
else
	C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s!!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sxx%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
is_root()  { [ "$(id -u)" -eq 0 ]; }

# Talk to the local tailscaled.
# TS_SOCKET overrides. When the system socket is missing, use the hint written
# by scripts/macos-userspace.sh (userspace networking, no root).
ts() {
	local sock="${TS_SOCKET:-}" hint
	if [ -z "$sock" ] && [ ! -S /var/run/tailscaled.socket ]; then
		hint="${XDG_CONFIG_HOME:-$HOME/.config}/opencode-vps/tailscale.socket"
		if [ -f "$hint" ]; then
			sock="$(head -n 1 "$hint" || true)"
		fi
	fi
	if [ -n "$sock" ]; then
		tailscale --socket "$sock" "$@"
	else
		tailscale "$@"
	fi
}

# Run a command as root, without assuming passwordless sudo.
as_root() {
	if is_root; then "$@"; else sudo "$@"; fi
}

# The unprivileged account the server runs as, even when invoked via sudo.
target_user() {
	if [ -n "${OC_USER:-}" ]; then
		printf '%s' "$OC_USER"
	elif is_root; then
		printf '%s' "${SUDO_USER:-root}"
	else
		id -un
	fi
}

user_home() {
	local u="$1" h=""
	if command -v getent >/dev/null 2>&1; then
		h="$(getent passwd "$u" 2>/dev/null | cut -d: -f6 || true)"
	fi
	if [ -z "$h" ] && command -v dscl >/dev/null 2>&1; then
		h="$(dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
	fi
	if [ -z "$h" ] && command -v python3 >/dev/null 2>&1; then
		h="$(python3 -c 'import pwd,sys; print(pwd.getpwnam(sys.argv[1]).pw_dir)' "$u" 2>/dev/null || true)"
	fi
	[ -n "$h" ] || die "cannot resolve home directory for user '$u'"
	printf '%s' "$h"
}

# Run a command as the target user, with their HOME and login environment.
runas_user() {
	local u="$1"; shift
	if [ "$(id -un)" = "$u" ]; then
		"$@"
	else
		sudo -u "$u" -H "$@"
	fi
}

# 32 chars, [A-Za-z0-9] only: typeable on a phone, safe in env files and URLs.
gen_password() {
	head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-32
}

# Linux keeps the password in /etc/opencode/env. The managed background service
# (macOS, and Linux `serve --service`) keeps a copy in service.json, mode 0600.
read_password() {
	local svc
	if [ -f "$OC_ENV_FILE" ]; then
		if [ -r "$OC_ENV_FILE" ]; then
			sed -n 's/^OPENCODE_PASSWORD=//p' "$OC_ENV_FILE" | head -n1
		else
			as_root sed -n 's/^OPENCODE_PASSWORD=//p' "$OC_ENV_FILE" | head -n1
		fi
		return 0
	fi
	svc="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/service.json"
	[ -f "$svc" ] || return 0
	python3 -c '
import json, sys
try:
    pw = json.load(open(sys.argv[1])).get("password") or ""
except Exception:
    pw = ""
if pw:
    sys.stdout.write(pw)
' "$svc"
}

# MagicDNS name for this node, without trailing dot. Empty when unavailable.
tailnet_dns() {
	command -v tailscale >/dev/null 2>&1 || return 0
	ts status --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
name = (d.get("Self") or {}).get("DNSName") or ""
print(name.rstrip("."))
' 2>/dev/null || true
}

json_escape() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n\r\t'
}

# GET url with the server's basic auth. When userspace tailscaled has no
# tunnel interface, retry through its localhost SOCKS proxy.
curl_ok_tailnet() {
	local url="$1" pw="$2" t="${3:-8}"
	local hint="${XDG_CONFIG_HOME:-$HOME/.config}/opencode-vps/tailscale.socket"
	if curl -fsS --max-time "$t" -u "opencode:${pw}" "$url" >/dev/null 2>&1; then
		return 0
	fi
	if [ -f "$hint" ]; then
		curl -fsS --max-time "$t" --socks5-hostname 127.0.0.1:1055 \
			-u "opencode:${pw}" "$url" >/dev/null 2>&1
	else
		return 1
	fi
}

port_in_use_by_other() {
	local port="$1"
	if command -v ss >/dev/null 2>&1; then
		ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
		return
	fi
	if command -v lsof >/dev/null 2>&1; then
		lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
		return
	fi
	return 1
}
