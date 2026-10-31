# AGENTS.md

Runbook for an AI agent setting up a VPS so that OpenCode is reachable from a
phone and a laptop over Tailscale. Follow it in order. Every phase is
idempotent: re-running is safe and is the correct response to an interrupted
run.

Human-facing overview: `README.md`. Background: `docs/architecture.md`.

---

## 1. What you are building

```
phone / laptop  ──Tailscale (WireGuard)──►  VPS
                                            tailscale serve :443
                                              └─► 127.0.0.1:49374 (opencode serve)
                                                    └─► repos + agent execution
```

Two outcomes must be true at the end:

1. `https://<host>.<tailnet>.ts.net` serves the OpenCode web UI, authenticated.
2. `opencode --server https://<host>.<tailnet>.ts.net` works from the laptop TUI.

---

## 2. Non-negotiable rules

- **Never** bind the server to `0.0.0.0` on this host. `127.0.0.1` only.
- **Never** run `tailscale funnel`. `serve` is the only sanctioned exposure.
- **Never** commit, echo into a PR/issue, or paste into logs the value of
  `OPENCODE_PASSWORD` or any provider key. Reporting it once to the operator in
  the direct conversation is acceptable; nothing further.
- **Never** edit tailnet ACLs, delete OpenCode data, or run
  `scripts/uninstall.sh --purge` without an explicit human instruction.
- **Never** invent provider credentials or run interactive `opencode auth login`
  on the human's behalf. Ask them to do it; it needs a browser/device flow.
- Do not run this as `root` as the service user. Root is for `sudo` only; the
  server runs as an unprivileged account.

---

## 3. Inputs to collect before starting

Ask the operator for these. Do not guess.

| Input | Why | Default if they decline |
| --- | --- | --- |
| Linux account to run the server | unit `User=`, home for data | the invoking sudo user |
| Tailscale auth key (`tskey-auth-...`) | unattended join | stop and ask the human to run `sudo tailscale up` (no `--ssh`) |
| Port | only if 49374 is taken | 49374 |
| Confirmation that MagicDNS + HTTPS certs are enabled | `serve` cannot issue a cert otherwise | stop at phase 4 and ask |
| Provider auth (API key or device login) | the agent is useless without a model | ask the human to run `opencode auth login` |

Also confirm: is this a fresh host, and may you install packages with `sudo`?

---

## 4. Preconditions (verify, do not assume)

```bash
id -u                                   # root? use sudo, not the service user
uname -s                                # Darwin -> scripts/macos-setup.sh
command -v systemctl                    # Linux path; absent on macOS
curl -fsS https://opencode.ai >/dev/null # outbound HTTPS
```

- **macOS:** run `./scripts/macos-setup.sh`. Do not invent a second supervisor.
  The launch agent in `launchd/` is the supported one. Use
  `scripts/macos-userspace.sh` only when the operator cannot install the
  Tailscale app or a root daemon, and say so in the final report.
- **No systemd and not macOS:** use `docker/compose.yaml` and document that
  choice. Do not hand-roll a supervisor. Docker does not get phone QR pairing
  unless the container is the managed service; prefer a native install for the
  OpenCode app.

---

## 5. Phases

Run from the repo root.

On macOS, stop after this. Do not run the Linux phases.

```bash
./scripts/macos-setup.sh
./scripts/pair.sh
```

No admin account: `./scripts/macos-userspace.sh`, then `macos-setup.sh`. Say that in the final report. Password rotation is `./scripts/rotate-password.sh`.

On Linux, `sudo` is required for the phases below.

### Phase 0 — clone

```bash
git clone https://github.com/joe-broadhead/opencode-vps.git ~/opencode-vps
cd ~/opencode-vps
chmod +x scripts/*.sh laptop/*.sh laptop/oc-remote launchd/*.sh
```

Pass criteria: every script parses cleanly before you execute anything:

```bash
for f in scripts/*.sh laptop/*.sh launchd/*.sh; do bash -n "$f" || exit 1; done
```

### Phase 1 — OpenCode CLI

```bash
sudo ./scripts/10-install-opencode.sh
```

Pass: prints `opencode v2.x.y`. Fail: check `~<user>/.local/bin` on PATH.

### Phase 2 — Tailscale

```bash
sudo TS_AUTHKEY=tskey-auth-... ./scripts/20-install-tailscale.sh
# or, without a key:
sudo ./scripts/20-install-tailscale.sh
```

Exit code **2** means a human must complete a browser login. Stop and report
exactly:

> Run `sudo tailscale up` on the host, approve the URL it prints, then tell
> me to continue. Do not pass `--ssh` unless the operator asked for tailnet SSH.

Pass: prints a `100.x.y.z` address and a `<host>.<tailnet>.ts.net` name.

### Phase 3 — systemd service

```bash
sudo ./scripts/30-install-service.sh
```

Generates `/etc/opencode/env` (root:0600) with a 32-char password on first run,
renders the unit, enables and restarts it, and waits for `/api/info`.

Pass: `service is up: http://127.0.0.1:49374`.
Fail: the script prints the last 40 journal lines; see `docs/troubleshooting.md`.

If the operator wants a specific password, pass it explicitly and do not log it:

```bash
sudo OC_PASSWORD='...' ./scripts/30-install-service.sh
```

### Phase 4 — publish on the tailnet

```bash
./scripts/40-enable-serve.sh
```

Exit code **2** means the tailnet lacks HTTPS certificates or MagicDNS. Stop and
report the remediation; do not retry in a loop.

Pass: `reachable at https://<host>.<tailnet>.ts.net`.

### Phase 5 — verify (the gate)

```bash
sudo ./scripts/verify.sh --json
```

Contract:

```json
{
  "ok": true,
  "url": "https://host.tailnet.ts.net",
  "checks": [
    { "id": "opencode-binary", "ok": true, "detail": "opencode v2.x.y" },
    { "id": "service-active",  "ok": true, "detail": "active" },
    { "id": "api-loopback",    "ok": true, "detail": "http://127.0.0.1:49374/api/info" },
    { "id": "tailscale",       "ok": true, "detail": "100.64.0.1 (host.tailnet.ts.net)" },
    { "id": "serve-mapping",   "ok": true, "detail": "https://host.tailnet.ts.net -> 127.0.0.1:49374" },
    { "id": "bind-loopback",   "ok": true, "detail": "127.0.0.1:49374" },
    { "id": "api-tailnet",     "ok": true, "detail": "https://host.tailnet.ts.net/api/info" }
  ]
}
```

Do not report success unless `ok` is `true`. If a check fails, use the `id` to
pick the row in `docs/troubleshooting.md`.

### Phase 6 — client handoff

Laptop (run on the laptop, not the VPS):

```bash
./laptop/install-macos.sh --url https://<host>.<tailnet>.ts.net
oc-remote
```

Phone (human action — you cannot scan for them):

1. Tailscale app, same tailnet.
2. App: on the host run `./scripts/pair.sh` and let them scan the QR or open the
   link before it expires (5 minutes, single use). Do not copy the link into
   a ticket, a commit, or a log.
3. Browser: open the URL, username `opencode`, password from `scripts/show-password.sh`,
   then Add to Home Screen.

Provider auth, if not already configured:

```bash
sudo -u <user> -H bash -lc 'opencode auth login'
```

This is interactive. Ask the human to run it, or to supply keys in
`/etc/opencode/env` followed by `sudo systemctl restart opencode`.

---

## 6. Final report template

Send exactly this shape, filling the values. The password goes only in the
direct channel, never into a file in the repo.

```
OpenCode VPS is up.

URL:       https://<host>.<tailnet>.ts.net
Username:  opencode
Password:  <32 chars>

Verified: service active, loopback API ok, tailnet serve ok, HTTPS ok
Phone:     Tailscale on -> ./scripts/pair.sh (QR, 5 min) or the URL in a browser
Laptop:    oc-remote   (wrapper installed, credentials in keychain)

Pending human steps: <provider auth / none>
```

---

## 7. Recovery quick reference

| State | Action |
| --- | --- |
| Script interrupted mid-phase | re-run the same phase; all phases are idempotent |
| Password lost | `./scripts/show-password.sh` (sudo on Linux if the env file is unreadable) |
| Password leaked / device lost | `./scripts/rotate-password.sh`, then remove the device from the tailnet |
| Port changed | re-run phase 3 **and** phase 4 |
| Want to tear down (keep data) | `sudo ./scripts/uninstall.sh` |
| Full removal | `sudo ./scripts/uninstall.sh --purge` (ask first) |
| Debugging | Linux: `journalctl -u opencode -n 100 --no-pager`. macOS: `~/Library/Logs/opencode-vps.log`. Then `tailscale serve status` |

---

## 8. Sources of truth

- Web UI, auth, ports: https://opencode.ai/v2/docs/cli/web/
- CLI, `--server`, background service: https://opencode.ai/v2/docs/cli/
- Troubleshooting: https://opencode.ai/v2/docs/troubleshooting/
- `tailscale serve`: https://tailscale.com/kb/1242/tailscale-serve
- Install: https://opencode.ai/v2/docs/

If the docs contradict this repo, the docs win; update this repo in the same
change.
