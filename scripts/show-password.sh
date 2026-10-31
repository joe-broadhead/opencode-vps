#!/usr/bin/env bash
# Print the server URL, username, and password.
# Linux reads /etc/opencode/env (root:0600, sudo when needed).
# macOS reads ~/.config/opencode/service.json.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

pw="$(read_password || true)"
[ -n "$pw" ] || die "no password in $OC_ENV_FILE (has the service been installed?)"

dns="$(tailnet_dns)"
if [ -z "$dns" ]; then
	printf 'Username  opencode\nPassword  %s\n' "$pw"
	warn "no MagicDNS name; enable it to get a URL"
	exit 0
fi

printf 'URL       https://%s\n' "$dns"
printf 'Username  opencode\n'
printf 'Password  %s\n' "$pw"
