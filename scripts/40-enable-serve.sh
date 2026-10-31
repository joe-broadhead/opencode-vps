#!/usr/bin/env bash
# Phase 4: publish the server on the tailnet over HTTPS via `tailscale serve`.
#
# Tailnet-only. Uses `serve`, never `funnel` (which would be public internet).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

port="${OC_PORT:-$OC_PORT_DEFAULT}"
need_cmd tailscale
need_cmd python3
need_cmd curl

pw="$(read_password || true)"
[ -n "$pw" ] || die "no server password yet. On Linux run scripts/30-install-service.sh. On macOS run scripts/macos-setup.sh"

dns="$(tailnet_dns)"
if [ -z "$dns" ]; then
	warn "MagicDNS name unavailable. Enable MagicDNS (and HTTPS Certificates) in the"
	warn "Tailscale admin console under DNS, then re-run this script."
	exit 2
fi

log "configuring tailscale serve: https://$dns -> http://127.0.0.1:$port"
if ! out="$(ts serve --bg --https=443 "http://127.0.0.1:$port" 2>&1)"; then
	warn "$out"
	case "$out" in
		*[Hh][Tt][Tt][Pp][Ss]*|*certificate*)
			warn "enable HTTPS certificates: admin console -> DNS -> HTTPS Certificates"
			warn "then re-run this script (cert issuance takes a moment)"
			exit 2
			;;
		*permission*|*denied*)
			warn "try: sudo tailscale set --operator=\$(id -un)  (or run this script with sudo)"
			exit 2
			;;
	esac
	exit 1
fi

log "waiting for the HTTPS endpoint (certificate issuance can take ~60s)"
for _ in $(seq 1 30); do
	if curl_ok_tailnet "https://$dns/api/info" "$pw" 8; then
		ok "reachable at https://$dns"
		ts serve status || true
		exit 0
	fi
	sleep 2
done

warn "serve is configured but https://$dns did not answer yet."
warn "check: tailscale serve status ; tailscale cert $dns"
warn "common cause: HTTPS certificates not enabled for the tailnet."
exit 1
