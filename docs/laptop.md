# Laptop

Two ways in, same server, same sessions.

## TUI (recommended)

```bash
./laptop/install-macos.sh --url https://<host>.<tailnet>.ts.net
oc-remote                 # TUI in the current directory
oc-remote ~/code/project  # another directory
oc-remote run "tests?"    # any opencode subcommand
```

The wrapper resolves credentials in this order:

1. `OPENCODE_VPS_URL` + `OPENCODE_PASSWORD` environment variables.
2. `~/.config/opencode-vps/url` + the OS keychain (`security` on macOS,
   `secret-tool` on Linux).
3. `~/.config/opencode-vps/password` (0600) as a last resort.

The installer verifies the URL and password with `GET /api/info` before storing
anything, so a typo fails immediately rather than at first prompt. Prefer the
prompt over `--password` so the secret does not land in shell history.

The phone app does not use this password flow. On the host, `./scripts/pair.sh`
prints the QR and the one-time link. See [mobile.md](mobile.md).

## Web UI

Open the same URL in a desktop browser. Same cookie model as the phone.

## Notes

- `opencode` must exist locally for the TUI: `curl -fsSL https://opencode.ai/v2/install | bash`.
- Execution happens on the VPS. Paths you pass to `oc-remote` must exist there:
  `oc-remote ~/code/foo` opens `~/code/foo` **on the server**, not on the laptop.
  For local projects, push/pull through git and use the server-side clone.
- Updating the local CLI is safe: the client and server negotiate over HTTP.
  Keep them within a major version of each other.
- If the server URL changes (new machine, new tailnet name), re-run the installer;
  it overwrites the stored URL.
