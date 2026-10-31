# opencode-vps

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/joe-broadhead/opencode-vps/actions/workflows/ci.yml/badge.svg)](https://github.com/joe-broadhead/opencode-vps/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/joe-broadhead/opencode-vps)](https://github.com/joe-broadhead/opencode-vps/releases)
[![OpenCode](https://img.shields.io/badge/OpenCode-v2-111111.svg)](https://opencode.ai/v2/docs/cli/web/)

**One OpenCode server. Every other device is a client.**

Phone, laptop TUI, and browser share the same sessions.
The server binds to loopback. [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) is the only way in.

[Security](SECURITY.md) ·
[macOS host](docs/macos.md) ·
[Linux host](docs/linux.md) ·
[Phone and QR](docs/mobile.md) ·
[Laptop TUI](docs/laptop.md)

</div>

---

## What it does

OpenCode's web UI and TUI are clients of one server. This repo installs that server on a machine you choose and publishes it on your tailnet:

```
phone / laptop  ── Tailscale ──►  host
                                  tailscale serve :443
                                    └─► 127.0.0.1:49374
                                          └─► your repos, your tools
```

Execution happens on the host. A path you pass from a laptop is a path on the host. Locking your phone does not stop the agent.

Two ways to sign a client in:

| Client | How |
| --- | --- |
| OpenCode app on a phone | `./scripts/pair.sh` prints a QR code and a one-time link |
| Mobile or desktop browser | Open the HTTPS URL. Username `opencode`, then the server password |
| Laptop TUI | `oc-remote` sends the password for you |

The pairing link expires in 5 minutes and works once. The browser cookie and the app session last 30 days. Rotating the password signs every client out.

## Quick start

Prerequisites: a [Tailscale](https://tailscale.com) account with **MagicDNS** and **HTTPS certificates** turned on (admin console → DNS).

### macOS host

```bash
git clone https://github.com/joe-broadhead/opencode-vps.git
cd opencode-vps
# Tailscale app installed and signed in, then:
./scripts/macos-setup.sh
./scripts/pair.sh
```

No admin account on that Mac: `./scripts/macos-userspace.sh`, then `./scripts/macos-setup.sh`. Read the trade-off in [docs/macos.md](docs/macos.md) before you use userspace networking.

### Linux host (systemd)

```bash
git clone https://github.com/joe-broadhead/opencode-vps.git
cd opencode-vps
sudo ./scripts/setup.sh --user "$USER"
./scripts/pair.sh
```

Unattended join, still with tailnet SSH left off:

```bash
sudo TS_AUTHKEY=tskey-auth-... ./scripts/setup.sh --user "$USER"
```

Set `TS_SSH=1` only when you deliberately want Tailscale SSH.

### Laptop

On the laptop (macOS or Linux), after the host prints a URL:

```bash
./laptop/install-macos.sh --url https://<host>.<tailnet>.ts.net
oc-remote
```

The installer prompts for the password and stores it in the macOS keychain or the Linux secret service. It checks `GET /api/info` before it writes anything.

### Phone

1. Install Tailscale and sign in to the same tailnet.
2. For the OpenCode app, scan the QR from `./scripts/pair.sh` or paste the pairing link.
3. For Safari or Chrome, open `https://<host>.<tailnet>.ts.net`, sign in, then Share → Add to Home Screen.

Details: [docs/mobile.md](docs/mobile.md).

## Commands

| Command | Where | Purpose |
| --- | --- | --- |
| `scripts/setup.sh` | Linux | All phases. On macOS this hands off to `macos-setup.sh` |
| `scripts/macos-setup.sh` | macOS | Launch agent, loopback server, Tailscale Serve |
| `scripts/macos-userspace.sh` | macOS, no root | Userspace `tailscaled` when the app is not an option |
| `scripts/pair.sh` | host | One-time QR and pairing link for the phone app |
| `scripts/verify.sh [--json]` | host | Reachability and bind checks |
| `scripts/show-password.sh` | host | Print URL, username, and password |
| `scripts/rotate-password.sh` | host | New password, every client signed out |
| `scripts/uninstall.sh [--purge]` | host | Remove the server and the Serve mapping |
| `laptop/install-macos.sh` | laptop | Store the URL and install `oc-remote` |

Linux phases (`10` through `40`) are idempotent. Re-run the phase that failed.

## Documentation

| Topic | Page |
| --- | --- |
| How a request moves | [docs/architecture.md](docs/architecture.md) |
| Linux / systemd | [docs/linux.md](docs/linux.md) |
| macOS / launchd | [docs/macos.md](docs/macos.md) |
| Phone, QR, browser | [docs/mobile.md](docs/mobile.md) |
| Laptop TUI | [docs/laptop.md](docs/laptop.md) |
| Docker, isolated filesystem | [docs/docker.md](docs/docker.md) |
| Threat model | [docs/security.md](docs/security.md) |
| When something fails | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Agent runbook | [AGENTS.md](AGENTS.md) |

## Security, in short

- The server listens on `127.0.0.1` only. `tailscale funnel` is never used.
- The password is a shell on that machine: the agent runs as the service user.
- Pairing links and QR codes are bearer tokens. Do not commit them or paste them into tickets.
- Tailscale SSH is off unless you set `TS_SSH=1`.
- Provider keys stay in `opencode auth login` or in a `0600` env file. Nothing in this repo is a credential.

The full model, rotation steps, and ACL sketch are in [docs/security.md](docs/security.md).

## Project layout

```
AGENTS.md                 agent runbook
docs/                     host, client, and security guides
scripts/                  idempotent setup, pairing, verify
systemd/opencode.service.in
launchd/                  macOS agent template and entrypoint
laptop/                   oc-remote installer
docker/compose.yaml       optional isolated filesystem
```

## Notes

- Keep the laptop CLI and the host server on the same major version. They negotiate over HTTP. Phase 1 does not upgrade an existing CLI. As the service user, run `opencode upgrade`, then restart the service.
- A tag `vX.Y.Z` publishes a GitHub release from that commit.
- `opencode pair` targets the managed background service (`opencode serve --service`). Both the systemd unit and the macOS agent run that mode.
- Repositories the agent should edit must exist on the host. Push and pull through git.
- Changing the port means re-running the service install and `tailscale serve`.

Upstream reference: <https://opencode.ai/v2/docs/cli/web/>

## License

[MIT](LICENSE) © [Joe Broadhead](https://github.com/joe-broadhead)
