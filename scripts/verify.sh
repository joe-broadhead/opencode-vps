#!/usr/bin/env bash
# Verification gate. Read-only. Exit 0 only when every check passes.
#
#   ./scripts/verify.sh          human-readable
#   ./scripts/verify.sh --json   machine-readable (agents parse this)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

JSON=0
[ "${1:-}" = "--json" ] && JSON=1

u="$(target_user)"
port="${OC_PORT:-$OC_PORT_DEFAULT}"
records=()
fail=0

emit() { # id status(ok|bad) detail
	local id="$1" st="$2" det="$3" bool="true"
	[ "$st" = "ok" ] || { bool="false"; fail=1; }
	records+=("{\"id\":\"$(json_escape "$id")\",\"ok\":$bool,\"detail\":\"$(json_escape "$det")\"}")
	if [ "$JSON" -eq 0 ]; then
		if [ "$st" = "ok" ]; then ok "$id: $det"; else warn "$id: $det"; fi
	fi
}

# 1. binary
if v="$(runas_user "$u" bash -lc 'opencode --version' 2>/dev/null)"; then
	emit opencode-binary ok "$v"
else
	emit opencode-binary bad "opencode not runnable as $u"
fi

# 2. service (systemd unit, or the macOS launch agent)
if command -v systemctl >/dev/null 2>&1 && systemctl cat opencode.service >/dev/null 2>&1; then
	st="$(systemctl is-active opencode.service 2>/dev/null || true)"
	if [ "$st" = "active" ]; then
		emit service-active ok "active"
	else
		emit service-active bad "${st:-missing}"
	fi
elif command -v launchctl >/dev/null 2>&1 && launchctl print "gui/$(id -u)/com.opencode.vps" 2>/dev/null | grep -q "state = running"; then
	emit service-active ok "launchd com.opencode.vps running"
else
	emit service-active bad "opencode service is not running (systemd unit or launchd com.opencode.vps)"
fi

pw="$(read_password || true)"
dns="$(tailnet_dns)"

# 3. loopback API
if [ -z "$pw" ]; then
	emit api-loopback bad "password unreadable (run with sudo/root)"
elif curl -fsS -u "opencode:$pw" "http://127.0.0.1:$port/api/info" >/dev/null 2>&1; then
	emit api-loopback ok "http://127.0.0.1:$port/api/info"
else
	emit api-loopback bad "no response on 127.0.0.1:$port"
fi

# 4. tailscale
ip="$(ts ip -4 2>/dev/null | head -n1 || true)"
if [ -n "$ip" ]; then
	emit tailscale ok "$ip ($dns)"
else
	emit tailscale bad "not connected"
fi

# 5. serve mapping
if [ -n "$dns" ] && ts serve status 2>/dev/null | grep -q "$dns"; then
	emit serve-mapping ok "https://$dns -> 127.0.0.1:$port"
else
	emit serve-mapping bad "no serve mapping for ${dns:-<no magicdns>}"
fi

# 6. loopback only (never a wildcard or LAN bind)
bind_ok=0
binds=""
if command -v lsof >/dev/null 2>&1; then
	binds="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}')"
elif command -v ss >/dev/null 2>&1; then
	binds="$(ss -ltn 2>/dev/null | awk '{print $4}' | grep -E "[:.]${port}$" || true)"
fi
if [ -n "$binds" ] \
	&& printf '%s\n' "$binds" | grep -q "127.0.0.1:${port}" \
	&& ! printf '%s\n' "$binds" | grep -Eq "^(0\\.0\\.0\\.0|\\*|\\[::\\]):${port}$"; then
	bind_ok=1
fi
if [ "$bind_ok" -eq 1 ]; then
	emit bind-loopback ok "127.0.0.1:$port"
else
	emit bind-loopback bad "expected 127.0.0.1:$port and no wildcard listener"
fi

# 7. HTTPS end-to-end over the tailnet.
# Userspace tailscaled has no tunnel interface, so the host cannot hairpin to
# its own tailnet IP. curl_ok_tailnet retries through the localhost SOCKS proxy.
if [ -n "$pw" ] && [ -n "$dns" ] && curl_ok_tailnet "https://$dns/api/info" "$pw" 12; then
	emit api-tailnet ok "https://$dns/api/info"
else
	emit api-tailnet bad "https://${dns:-<none>} not reachable or not authenticated"
fi

if [ "$JSON" -eq 1 ]; then
	printf '{"ok":%s,"url":"%s","checks":[%s]}\n' \
		"$([ "$fail" -eq 0 ] && echo true || echo false)" \
		"$(json_escape "https://${dns:-}")" \
		"$(IFS=,; printf '%s' "${records[*]}")"
else
	echo
	if [ "$fail" -eq 0 ]; then
		ok "all checks passed — https://${dns}"
	else
		warn "one or more checks failed; see docs/troubleshooting.md"
	fi
fi

exit "$fail"
