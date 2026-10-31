#!/bin/sh
# Foreground entrypoint for the macOS launch agent.
# launchd owns this process. `serve --service` stays in the foreground and
# registers the managed OpenCode service that `opencode pair` talks to.
set -eu

if [ -f "${HOME}/.config/opencode/env" ]; then
	set -a
	# Operator-provided KEY=value file. Same file a login shell would source.
	# shellcheck disable=SC1091
	. "${HOME}/.config/opencode/env"
	set +a
fi

bin="${OPENCODE_BIN:-opencode}"
port="${OPENCODE_PORT:-49374}"
exec "$bin" serve --service --hostname 127.0.0.1 --port "$port"
