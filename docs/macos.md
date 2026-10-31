# macOS host

Use this when the machine that runs OpenCode is a Mac. The launch agent starts the server at login and restarts it if it exits. Sessions and files live on that Mac.

## Supported path

1. Install the [Tailscale app](https://tailscale.com/download/macos) and sign in.
2. In the admin console, turn on MagicDNS and HTTPS Certificates.
3. Clone this repo and run:

```bash
./scripts/macos-setup.sh
./scripts/pair.sh
```

`macos-setup.sh` installs the OpenCode CLI if it is missing, pins the server to `127.0.0.1`, installs a launch agent (`com.opencode.vps`), and publishes HTTPS with `tailscale serve`. It does not enable Tailscale SSH and it does not enable Funnel.

The agent entrypoint is `launchd/serve.sh`. It stays in the foreground, sources `~/.config/opencode/env` when that file exists (provider keys, mode `0600`), and runs:

```bash
opencode serve --service --hostname 127.0.0.1 --port 49374
```

`--service` is what registers the managed background service. `opencode pair` and the phone QR talk to that service. A plain `opencode serve` without `--service` will not.

Re-run `./scripts/macos-setup.sh` after you install a toolchain the agent should see. The plist records `PATH` from the shell that ran setup.

Phase 1 does not upgrade an OpenCode that is already installed. Upgrade with `opencode upgrade`, then `launchctl kickstart -k "gui/$(id -u)/com.opencode.vps"`. Rotate the server password with `./scripts/rotate-password.sh`.

## Flags

| Flag | Effect |
| --- | --- |
| `--port N` | Listen port. Default `49374` |
| `--no-serve` | Start the server and skip Tailscale Serve |
| `--skip-opencode` | Do not install or relink the CLI |
| `--rotate-password` | New password. Signs every client out |
| `--tailnet-key KEY` | `tailscale up --auth-key` when the node is logged out |
| `--json` | Machine-readable `verify.sh` output |

`--user` must be the account you are logged in as. launchd agents in `~/Library/LaunchAgents` run as that user.

## Without administrator rights

`brew services start tailscale` and the Tailscale app both want a privileged daemon. If you cannot grant that, userspace networking still lets other devices reach Serve:

```bash
brew install tailscale
./scripts/macos-userspace.sh
./scripts/macos-setup.sh
```

What you give up:

- This Mac has no Tailscale tunnel interface. Programs on it do not route to tailnet IPs by themselves. A localhost SOCKS proxy on `127.0.0.1:1055` exists so `verify.sh` can check the HTTPS URL from the host.
- `tailscaled` listens on a high TCP port on all interfaces so peers can connect. That port is Tailscale's own protocol, not OpenCode. Prefer the app when you can.
- The CLI socket is tightened to mode `0600`. The system daemon's socket is the better default when you have root.

`./scripts/macos-userspace.sh` prints a `tailscale up` command if the node is logged out. Approve it, then run `macos-setup.sh`.

Do not start the Homebrew `tailscale` service next to the userspace agent. They fight over the same node.

## Check

```bash
./scripts/verify.sh
./scripts/show-password.sh
./scripts/pair.sh
```

`verify.sh` fails if anything is listening on `0.0.0.0:49374` or `*:49374`.

Logs: `~/Library/Logs/opencode-vps.log`.

Restart:

```bash
launchctl kickstart -k "gui/$(id -u)/com.opencode.vps"
```

## Tear down

```bash
./scripts/uninstall.sh
```

That removes the OpenCode launch agent, the userspace Tailscale agent if this repo installed one, and the Serve mapping. It leaves the Tailscale app or formula installed, and it leaves `~/.local/state/tailscale` alone. `--purge` also deletes `~/.local/share/opencode` and `~/.config/opencode`. Ask before you do that: session history is in there.
