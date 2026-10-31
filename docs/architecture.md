# Architecture

```
┌──────────────────────────── host ───────────────────────────┐
│                                                             │
│  systemd or launchd                                        │
│    opencode serve --service --hostname 127.0.0.1 --port 49374│
│      ├── HTTP API  (Basic auth, user "opencode")            │
│      ├── web UI    (same origin, cookie session, 30 days)   │
│      └── sessions/agents/tools  ──►  repos on this machine  │
│                                                             │
│  tailscaled                                                 │
│    tailscale serve --bg --https=443 http://127.0.0.1:49374  │
│      └── TLS cert for <host>.<tailnet>.ts.net               │
└─────────────────────────────────────────────────────────────┘
                    ▲                        ▲
        Tailscale   │                        │   Tailscale
                    │                        │
              phone (Safari/PWA)       laptop (TUI: oc-remote,
                                       or a browser tab)
```

## Why this shape

- **Loopback bind.** `opencode serve` never listens on a public interface. The
  only way in is through `tailscale serve`, which terminates TLS and is
  reachable only from devices in the tailnet.
- **`serve`, not `funnel`.** Funnel would publish the port to the entire
  internet. There is no reason to do that here.
- **One server, many clients.** The TUI (`opencode --server ...`) and the web UI
  talk to the same process, so a session started on the phone is visible from
  the laptop.
- **Execution is server-side.** Every tool call runs on the VPS. Repositories
  must exist there. The phone is a thin client.

## Ports and paths

| Item | Value |
| --- | --- |
| Server port (default) | 49374 (macOS/Linux), configurable via `--port` |
| Public exposure | none; 443 on the tailnet IP only |
| Linux unit | `/etc/systemd/system/opencode.service` |
| macOS agent | `~/Library/LaunchAgents/com.opencode.vps.plist` |
| Secrets (Linux) | `/etc/opencode/env` (root:root 0600) |
| Secrets (managed service) | `~/.config/opencode/service.json` (0600) |
| Sessions/config | `~<user>/.local/share/opencode`, `~<user>/.config/opencode` |
| Logs | `journalctl -u opencode`, or `~/Library/Logs/opencode-vps.log` on macOS |

## Request flow

1. Phone resolves `<host>.<tailnet>.ts.net` via MagicDNS.
2. Tailscale encrypts the request (WireGuard) and routes it to the VPS.
3. `tailscaled` terminates TLS and proxies to `127.0.0.1:49374`.
4. OpenCode checks the session cookie; on first visit it challenges for the
   password (username `opencode`).
5. The agent works on the VPS filesystem and streams results back.

## What lives where

- `scripts/` — idempotent phases (install, service, serve, verify).
- `systemd/` — unit template; the installer substitutes user, home, binary path, port.
- `laptop/` — client-side wrapper and installer.
- `docker/` — optional container path with an isolated filesystem.
- `AGENTS.md` — the runbook agents follow; this doc is background, that doc is procedure.
