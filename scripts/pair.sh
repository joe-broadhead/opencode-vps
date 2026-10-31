#!/usr/bin/env bash
# Print a one-time pairing link and a QR code for the OpenCode phone app.
#
#   ./scripts/pair.sh
#   ./scripts/pair.sh --url https://host.tailnet.ts.net
#
# The link expires in 5 minutes and works once. It is a bearer credential:
# do not commit it, screenshot it into a ticket, or paste it into chat.
# Open the link in the phone's browser (Tailscale connected) or scan the QR
# from the OpenCode app. A browser that only wants a password can ignore this
# and open the bare https:// URL instead.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

URL=""

while [ $# -gt 0 ]; do
	case "$1" in
		--url) URL="${2:?}"; shift 2 ;;
		--url=*) URL="${1#*=}"; shift ;;
		-h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) die "unknown flag: $1 (try --help)" ;;
	esac
done

if [ -z "$URL" ]; then
	dns="$(tailnet_dns)"
	[ -n "$dns" ] || die "no MagicDNS name. Pass --url https://<host>.<tailnet>.ts.net"
	URL="https://${dns}"
fi

case "$URL" in
	https://*) ;;
	*) die "the pairing URL must be the https:// tailnet address" ;;
esac

need_cmd opencode
log "pairing against ${URL}"
log "the link works once and expires in 5 minutes"
exec opencode pair --url "$URL"
