# Linux host

Ubuntu or Debian with systemd. The unit runs as an unprivileged user and comes back after reboot.

```bash
git clone https://github.com/joe-broadhead/opencode-vps.git
cd opencode-vps
sudo ./scripts/setup.sh --user "$USER"
./scripts/pair.sh
```

## What the phases do

| Phase | Script | Result |
| --- | --- | --- |
| 1 | `scripts/10-install-opencode.sh` | OpenCode CLI for the service user, linked from `~/.local/bin` |
| 2 | `scripts/20-install-tailscale.sh` | Tailscale installed and logged in. SSH off unless `TS_SSH=1` |
| 3 | `scripts/30-install-service.sh` | Password, managed service config, systemd unit |
| 4 | `scripts/40-enable-serve.sh` | `tailscale serve --bg --https=443` to loopback |
| 5 | `scripts/verify.sh` | Binary, unit, loopback API, bind, tailnet, Serve, HTTPS |

Every phase is idempotent. If a run stops halfway, run that phase again. Phase 1 does not upgrade an OpenCode that is already installed. Upgrade with `opencode upgrade` as the service user, then `sudo systemctl restart opencode`.

The unit is `Type=simple`. `opencode serve --service` stays in the foreground under systemd and registers the managed service that pairing uses. The password is generated once into `/etc/opencode/env` (`root:root`, mode `0600`) and copied into the service user's OpenCode config. Later runs keep the existing password unless you pass `--rotate-password`.

## Useful flags

```bash
sudo ./scripts/setup.sh --user "$USER" --port 49375
sudo TS_AUTHKEY=tskey-auth-... ./scripts/setup.sh --user "$USER"
sudo TS_SSH=1 ./scripts/setup.sh --user "$USER"    # tailnet SSH, off by default
sudo ./scripts/setup.sh --user "$USER" --no-serve  # loopback only
sudo ./scripts/rotate-password.sh
sudo ./scripts/show-password.sh
```

Phase 2 exits `2` when a human has to approve `sudo tailscale up` in a browser. Phase 4 exits `2` when MagicDNS or HTTPS certificates are off. Fix the console setting and re-run. Do not loop.

## Provider login

The installer does not log in to a model provider.

```bash
sudo -u "$USER" -H opencode auth login
```

Or put provider keys in `/etc/opencode/env` and `sudo systemctl restart opencode`. Treat that file like a password.

## PATH inside the unit

systemd starts with a short `PATH`. If the agent cannot find `node`, `cargo`, or `python`, install them on the default path or extend `Environment=PATH=` in the unit, then `sudo systemctl daemon-reload && sudo systemctl restart opencode`.

## Tear down

```bash
sudo ./scripts/uninstall.sh           # stop the unit, drop Serve, keep data
sudo ./scripts/uninstall.sh --purge   # also delete OpenCode data and config
```

`--purge` deletes session history. Do not run it unless that is what you want.
