#!/usr/bin/env bash
# Phase 2: install and connect Tailscale (idempotent).
#
# Unattended: TS_AUTHKEY=<key> ./20-install-tailscale.sh
# Interactive: the human runs `sudo tailscale up` and approves in a browser.
# SSH on the tailnet is off unless TS_SSH=1.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! command -v tailscale >/dev/null 2>&1; then
	need_cmd curl
	log "installing tailscale"
	curl -fsSL https://tailscale.com/install.sh | as_root sh
fi

up_args=(--hostname "$(hostname -s)")
# Tailscale SSH is a remote shell. Leave it off unless the operator opts in.
if [ "${TS_SSH:-0}" = "1" ]; then
	up_args+=(--ssh)
fi

if ts ip -4 >/dev/null 2>&1; then
	ok "tailscale already connected: $(ts ip -4 | head -n1)"
else
	if [ -n "${TS_AUTHKEY:-}" ]; then
		log "connecting to the tailnet with an auth key"
		as_root ts up --auth-key "$TS_AUTHKEY" "${up_args[@]}"
		for _ in $(seq 1 30); do
			ts ip -4 >/dev/null 2>&1 && break
			sleep 1
		done
		ts ip -4 >/dev/null 2>&1 || die "tailscale did not come up; check 'tailscale status'"
	else
		warn "Tailscale needs a human step (no TS_AUTHKEY provided):"
		warn "  sudo tailscale up"
		warn "  then approve the login in the printed URL and re-run this script."
		warn "  (TS_SSH=1 also passes --ssh; leave it unset unless you want a tailnet shell.)"
		exit 2
	fi
fi

# Let the operator run `tailscale serve` without sudo.
if ! as_root ts set --operator="$(target_user)" 2>/dev/null; then
	warn "could not set tailscale operator; 'tailscale serve' may require sudo"
fi

dns="$(tailnet_dns)"
if [ -z "$dns" ]; then
	warn "no MagicDNS name detected. Enable MagicDNS in the Tailscale admin console"
	warn "(DNS page), then re-run. HTTPS access depends on it."
else
	ok "tailnet name: $dns"
fi
