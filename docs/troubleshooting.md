# Troubleshooting

Run `./scripts/verify.sh` first — it names the failing layer.

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Service restarts in a loop | `EnvironmentFile` missing, or binary path wrong | `journalctl -u opencode -n 50`; confirm `/etc/opencode/env` exists and `command -v opencode` as the service user |
| `verify.sh`: `api-loopback` fails | server still starting, port conflict, crash | `ss -ltnp \| grep 49374` or `lsof -nP -iTCP:49374 -sTCP:LISTEN`. Linux: `journalctl -u opencode -n 80`. macOS: `~/Library/Logs/opencode-vps.log` |
| `verify.sh`: `bind-loopback` fails | server is on `0.0.0.0` or `*` | stop it. Re-run setup. The only acceptable listener is `127.0.0.1` |
| `verify.sh`: `tailscale` fails | not logged in / key expired | `sudo tailscale up` (no `--ssh` unless you want a tailnet shell), or re-auth in the admin console |
| `tailscale serve` says HTTPS is not enabled | tailnet lacks HTTPS certs | admin console → DNS → enable MagicDNS **and** HTTPS Certificates |
| `tailscale serve` permission denied | operator not set | `sudo tailscale set --operator=$(id -un)` |
| `https://<host>.<tailnet>.ts.net` does not resolve | MagicDNS off, or device not in tailnet | enable MagicDNS; `tailscale status` on both devices |
| Works on laptop, not on phone | phone Tailscale disconnected, or key expired | open the Tailscale app, re-auth; check `tailscale status` |
| 401 in browser after setting a password | wrong password, or stale cookie from a rotated password | clear cookies for the host, authenticate again |
| 502 / connection reset from `tailscale serve` | backend down | `systemctl status opencode`, then `sudo systemctl restart opencode` |
| Agent cannot find `node`/`cargo`/`python` | systemd PATH is minimal | add the toolchain dir to `Environment=PATH=` in the unit, or install under `/usr/local/bin` |
| Agent works but cannot write files | service user lacks permissions on the repo | `chown`/ACLs, or run the service as the repo owner |
| Port already in use | leftover process from a manual `opencode serve` | `ss -ltnp \| grep 49374`, stop it, or install with `--port 49375` |
| Cert errors in `curl` from the VPS itself | cert not issued yet | wait ~60s; `tailscale cert <host>.<tailnet>.ts.net` |
| Web UI looks stale after upgrade | browser cache / old server | `sudo systemctl restart opencode`, hard reload |

## Diagnostic bundle

```bash
systemctl status opencode --no-pager
journalctl -u opencode -n 100 --no-pager
ss -ltnp | grep -E '49374|:443'
tailscale status
tailscale serve status
tailscale cert "$(tailscale status --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"
curl -sS -o /dev/null -w '%{http_code}\n' -u "opencode:$PW" https://<host>.<tailnet>.ts.net/api/info
```

Redact the password before sharing any of this.

## Known sharp edges

- `opencode serve` prints a generated password once when `OPENCODE_PASSWORD` is
  unset and the process is not the managed service. This repo sets the password.
  On Linux the source of truth is `/etc/opencode/env`. On macOS it is
  `~/.config/opencode/service.json` (mode `0600`). `scripts/show-password.sh`
  reads whichever exists.
- Changing the port requires re-running the service install **and** Serve
  (the mapping still points at the old port).
- `./scripts/pair.sh` mints a one-time link and QR for the managed service
  (`opencode serve --service`). Both installers use that mode. A password login
  in the browser does not require a pairing link. `opencode pair --remote` is
  not part of this setup.
- On macOS userspace Tailscale, `curl https://<host>.<tailnet>.ts.net` from the
  host itself can time out because there is no tunnel interface. `verify.sh`
  and `40-enable-serve.sh` retry through `127.0.0.1:1055`. Phones and laptops
  with the real Tailscale app do not need that proxy.
