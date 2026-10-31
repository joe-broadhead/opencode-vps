#!/usr/bin/env bash
# Rotate the server password. Signs out every existing web/app session.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

export ROTATE_PASSWORD=1
export OC_USER="${OC_USER:-$(target_user)}"
export OC_PORT="${OC_PORT:-$OC_PORT_DEFAULT}"

warn "rotating signs out every browser, phone, and laptop session"
if [ "$(uname -s)" = "Darwin" ]; then
	exec "$HERE/macos-setup.sh" --rotate-password --skip-opencode
fi
"$HERE/30-install-service.sh"
"$HERE/verify.sh" || true

echo
"$HERE/show-password.sh"
