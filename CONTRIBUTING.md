# Contributing

Bugs, docs fixes, and small script fixes are welcome.

## Before you open a pull request

```bash
bash -n scripts/*.sh laptop/*.sh launchd/*.sh
shellcheck scripts/*.sh laptop/*.sh launchd/*.sh
```

CI runs the same check on pushes to `master` and on pull requests. A tag `vX.Y.Z` runs the check again and publishes a GitHub release for that commit.

## Ground rules

- Do not commit secrets, tailnet hostnames, pairing links, or generated launch agents from a real machine.
- Do not add `tailscale funnel`, and do not bind `opencode serve` to `0.0.0.0` on the host.
- Keep scripts idempotent. A second run on a healthy host should change nothing important.
- If upstream OpenCode docs disagree with this repo, the docs win. Update the repo in the same change.
- Password and pairing output stays on the operator's terminal. Do not write either to a world-readable file or to a log this repo creates.

## Docs

User-facing steps live under `docs/`. `AGENTS.md` is the ordered runbook for an automated setup. If you change a phase, update both.
