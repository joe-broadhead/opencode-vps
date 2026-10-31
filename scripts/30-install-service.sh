#!/usr/bin/env bash
# Phase 3: install and start the systemd service (idempotent).
#
# Generates a password on first run, keeps it on subsequent runs.
# ROTATE_PASSWORD=1 forces a new one (invalidates every existing web session).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
u="$(target_user)"
h="$(user_home "$u")"
port="${OC_PORT:-$OC_PORT_DEFAULT}"
pw="${OC_PASSWORD:-}"

command -v systemctl >/dev/null 2>&1 || die "systemd not found; use the docker/ path on this host"

bin="$(runas_user "$u" bash -lc 'command -v opencode' 2>/dev/null || true)"
[ -n "$bin" ] || die "opencode is not installed for $u; run scripts/10-install-opencode.sh first"

as_root install -d -m 755 "$OC_CONF_DIR"

existing="$(read_password || true)"
if [ -z "$existing" ] || [ "${ROTATE_PASSWORD:-0}" = "1" ]; then
	[ -n "$pw" ] || pw="$(gen_password)"
	log "writing server password to $OC_ENV_FILE"
	tmp="$(mktemp)"
	if as_root test -f "$OC_ENV_FILE"; then
		# Preserve operator-added variables (provider keys etc.).
		as_root grep -v '^OPENCODE_PASSWORD=' "$OC_ENV_FILE" > "$tmp" 2>/dev/null || true
	fi
	printf 'OPENCODE_PASSWORD=%s\n' "$pw" >> "$tmp"
	as_root install -m 600 -o root -g root "$tmp" "$OC_ENV_FILE"
	rm -f "$tmp"
else
	pw="$existing"
	log "keeping existing password from $OC_ENV_FILE"
fi

# Stop our unit before the port check so a second run is not blocked by itself.
# systemctl stop does not trip Restart=always.
if as_root systemctl cat opencode.service >/dev/null 2>&1; then
	as_root systemctl stop opencode.service || true
	sleep 1
fi

if port_in_use_by_other "$port"; then
	warn "something else is already listening on port $port:"
	ss -ltnp 2>/dev/null | grep -E "[:.]${port}\b" >&2 || true
	die "pick another port with --port"
fi

log "syncing managed service config for pairing (hostname, port, password)"
# `service set` writes the service user's config and stops a managed server.
# The password is an argument; do not echo this command.
runas_user "$u" "$bin" service set hostname 127.0.0.1
runas_user "$u" "$bin" service set port "$port"
runas_user "$u" "$bin" service set password "$pw"

log "rendering $OC_UNIT_PATH"
tmp_unit="$(mktemp)"
sed \
	-e "s|@OC_USER@|$u|g" \
	-e "s|@OC_GROUP@|$(id -gn "$u")|g" \
	-e "s|@OC_HOME@|$h|g" \
	-e "s|@OC_BIN@|$bin|g" \
	-e "s|@OC_PORT@|$port|g" \
	-e "s|@OC_ENV_FILE@|$OC_ENV_FILE|g" \
	"$REPO_DIR/systemd/opencode.service.in" > "$tmp_unit"
as_root install -m 644 "$tmp_unit" "$OC_UNIT_PATH"
rm -f "$tmp_unit"

as_root systemctl daemon-reload
as_root systemctl enable opencode.service >/dev/null
as_root systemctl restart opencode.service

log "waiting for the API on 127.0.0.1:$port"
for _ in $(seq 1 40); do
	if curl -fsS -u "opencode:$pw" "http://127.0.0.1:$port/api/info" >/dev/null 2>&1; then
		ok "service is up: http://127.0.0.1:$port"
		exit 0
	fi
	sleep 1
done

warn "service did not answer within 40s. Recent logs:"
as_root journalctl -u opencode.service -n 40 --no-pager >&2 || true
die "startup failed"
