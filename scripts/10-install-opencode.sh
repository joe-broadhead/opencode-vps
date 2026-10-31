#!/usr/bin/env bash
# Phase 1: install the OpenCode CLI for the target user (idempotent).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

u="$(target_user)"
h="$(user_home "$u")"
log "target user: $u ($h)"

link_cli() {
	local bin="$h/.opencode/bin/opencode"
	if [ -x "$bin" ]; then
		runas_user "$u" mkdir -p "$h/.local/bin"
		runas_user "$u" ln -sfn "$bin" "$h/.local/bin/opencode"
	fi
}

if [ -x "$h/.opencode/bin/opencode" ] || runas_user "$u" bash -lc 'command -v opencode >/dev/null 2>&1'; then
	link_cli
	v="$(runas_user "$u" bash -lc 'export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"; opencode --version' 2>/dev/null || echo 'unknown version')"
	ok "opencode already installed: $v"
	exit 0
fi

need_cmd curl
log "installing opencode V2 for $u"
runas_user "$u" bash -lc 'curl -fsSL https://opencode.ai/v2/install | bash'
link_cli

if ! runas_user "$u" bash -lc 'export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"; command -v opencode >/dev/null 2>&1'; then
	die "install finished but 'opencode' is not on PATH for $u (expected ~/.local/bin or ~/.opencode/bin)"
fi

ok "$(runas_user "$u" bash -lc 'export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"; opencode --version')"
warn "providers are NOT configured yet: the operator must run 'opencode auth login' as $u"
