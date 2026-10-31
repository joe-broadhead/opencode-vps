#!/usr/bin/env bash
# Remove the service and the tailnet mapping. Keeps data unless --purge.
#
#   ./scripts/uninstall.sh           stop + disable + remove unit/env/serve
#   ./scripts/uninstall.sh --purge   also delete OpenCode data and config
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

if command -v systemctl >/dev/null 2>&1; then
	as_root systemctl disable --now opencode.service 2>/dev/null || true
	as_root rm -f "$OC_UNIT_PATH"
	as_root systemctl daemon-reload || true
fi

if command -v launchctl >/dev/null 2>&1; then
	uid="$(id -u)"
	launchctl bootout "gui/${uid}/com.opencode.vps" 2>/dev/null || true
	launchctl bootout "gui/${uid}/com.opencode.vps.tailscaled" 2>/dev/null || true
	rm -f "${HOME}/Library/LaunchAgents/com.opencode.vps.plist"
	rm -f "${HOME}/Library/LaunchAgents/com.opencode.vps.tailscaled.plist"
	rm -f "${HOME}/.local/lib/opencode-vps/serve.sh"
	rm -f "${HOME}/.local/lib/opencode-vps/userspace-tailscaled.sh"
	if command -v opencode >/dev/null 2>&1; then
		opencode service stop >/dev/null 2>&1 || true
	fi
	log "Tailscale itself is left installed. Userspace state, if any, is in ~/.local/state/tailscale"
fi

# Remove the HTTPS mapping for port 443 if we own it. Never touches funnel.
if command -v tailscale >/dev/null 2>&1; then
	ts serve --https=443 off 2>/dev/null || warn "could not remove serve mapping (check 'tailscale serve status')"
fi

# /etc/opencode/env exists on Linux. Skip sudo on a Mac where it was never created.
if [ -e "$OC_ENV_FILE" ] || [ -d "$OC_CONF_DIR" ]; then
	as_root rm -f "$OC_ENV_FILE"
	as_root rmdir "$OC_CONF_DIR" 2>/dev/null || true
fi
ok "service removed"

u="$(target_user)"
h="$(user_home "$u")"
if [ "$PURGE" -eq 1 ]; then
	warn "purging OpenCode data and config for $u"
	as_root rm -rf "$h/.local/share/opencode" "$h/.config/opencode"
	ok "data purged"
else
	log "data kept: $h/.local/share/opencode and $h/.config/opencode"
fi

log "remember to remove this machine from the tailnet if it is being retired"
