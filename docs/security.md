# Security

## The password is a shell on that box

The OpenCode agent runs tools as the service user, with that user's full
permissions: read/write files, run commands, reach the network. Anyone holding
the URL and password has that same access through the agent.

Consequences:

- Use a long random password. The installer generates 32 characters of
  `[A-Za-z0-9]`.
- Do not reuse it. Do not paste it into issues, PRs, chat logs, or screenshots.
- Rotate it with `./scripts/rotate-password.sh`. On Linux that uses sudo.
  Rotation signs every browser, app, and TUI session out immediately.
- Pairing links from `./scripts/pair.sh` are bearer tokens. They expire in five
  minutes and work once. A QR code on a screen is the same secret. Do not
  photograph it into chat or a ticket.
- Treat the phone and laptop as credentials: they hold 30-day cookies and
  keychain entries.

## Network exposure

| Control | State |
| --- | --- |
| Server bind | `127.0.0.1` only. `verify.sh` fails a wildcard listener |
| Public ingress | none (`tailscale funnel` is not used; `opencode pair --remote` is not used) |
| Tailnet ingress | HTTPS 443 via `tailscale serve` |
| Tailscale SSH | off unless `TS_SSH=1` |
| Host firewall | do not open 49374. SSH, if you want it, is your normal SSH, not Serve |
| TLS | automatic cert for `<host>.<tailnet>.ts.net` |

`tailscale serve` inherits tailnet ACLs. If the tailnet grows beyond personal
devices, add a tag for this host and restrict which users/devices may reach it
(admin console → Access Controls). Example policy shape:

```json
{
  "tagOwners": { "tag:opencode": ["autogroup:admin"] },
  "grants": [
    { "src": ["user@example.com"], "dst": ["tag:opencode"], "ip": ["443"] }
  ]
}
```

The installer does not pass `tailscale up --ssh`. Turn tailnet SSH on only with
`TS_SSH=1`, and turn it back off with `tailscale set --ssh=false`.

## Blast radius reduction

- Create a dedicated unprivileged account if the VPS hosts other things
  (`--user opencode`). The service already runs as a non-root user.
- Keep the agent out of `~/.ssh` and cloud credential files where practical;
  prefer per-project repositories.
- The docker path isolates the filesystem but *not* the network or mounted
  workspace: mount only the projects you want the agent to edit. Inside the
  container the process listens on `0.0.0.0` so Docker can proxy it. The
  published host port stays `127.0.0.1`. Do not change that mapping to
  `0.0.0.0:49374:49374`.
- macOS without root can run userspace Tailscale (`scripts/macos-userspace.sh`).
  Peers can reach Serve. The host has no tunnel interface, and `tailscaled`
  opens a high TCP port on all interfaces for its own protocol. Use the
  Tailscale app when you have admin rights.
- Backups: `~/.local/share/opencode` contains session history. Treat it as
  sensitive; it often contains code and prompts.

## Key rotation checklist

1. `./scripts/rotate-password.sh` (uses sudo on Linux).
2. Update the laptop keychain. Run `laptop/install-macos.sh --url ...` and type the new password when prompted. Do not put it in the command line if you can avoid shell history.
3. Open the URL on the phone, or run `./scripts/pair.sh` and scan the new QR.
4. If a device was lost, remove it from the tailnet (admin console → Machines)
   and rotate the Tailscale auth key if one was used for unattended setup.

## What the scripts never do

- Never bind `0.0.0.0` on a public interface.
- Never enable `tailscale funnel`.
- Never run `opencode pair --remote` (that publishes the server on the internet).
- Never pass `tailscale up --ssh` unless `TS_SSH=1` was requested.
- Never write the password or a pairing link to a world-readable file or to git.
- Never modify the tailnet ACLs.
