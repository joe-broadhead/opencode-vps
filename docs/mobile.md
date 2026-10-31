# Phone

The phone is a client. The agent keeps running on the host when the screen locks.

Tailscale has to be connected on the phone, on the same tailnet as the host. MagicDNS has to be on, or the hostname will not resolve.

## OpenCode app (QR or pairing link)

On the host:

```bash
./scripts/pair.sh
```

That runs `opencode pair --url https://<host>.<tailnet>.ts.net`. It prints a URL and a QR code.

- The link looks like `https://<host>.<tailnet>.ts.net/auth/connect/<token>`.
- It works **once** and expires in **5 minutes**.
- It is a bearer token. Anyone who opens it is signed in as the server user. Do not send it through chat, email, or a screenshot in a ticket.
- In the app, scan the QR or paste the link into the pairing field.
- You can also open the link in Safari or Chrome on the phone. Tailscale must be connected first, or the name will not resolve.

A successful pairing sets a session that lasts 30 days. Rotating the password signs it out.

Run `./scripts/pair.sh` again if the link expires before you use it. Each run mints a new link.

`opencode pair --remote` is a different feature. It exposes the server on the public internet through OpenTunnel. This repo does not use it. Do not pass `--remote` or `--yes`.

## Mobile browser

1. Open the Tailscale app and confirm the host is visible.
2. Open `https://<host>.<tailnet>.ts.net`.
3. Sign in. The username is `opencode`. The password is on the host: `sudo ./scripts/show-password.sh` (Linux) or `./scripts/show-password.sh` (macOS).
4. Share → **Add to Home Screen**.

The cookie lasts 30 days.

## Using it

- The same session is visible from `oc-remote` on a laptop.
- Attachments come from the host filesystem, not the phone's photo library.
- A community app such as [opencode-mobile](https://github.com/alvarolorentedev/opencode-mobile) can take a server URL and password. It is third-party. Prefer the pairing link or the browser unless you have decided you trust it with the password.

## If the phone cannot connect

1. Toggle Tailscale off and on. Confirm the host is listed.
2. On the host, `tailscale status` should list the phone.
3. Re-authenticate in the Tailscale app if the node key expired.
4. Open the same URL on a laptop that is on the tailnet. If the laptop works, the phone's tailnet membership is the problem.
5. If the name does not resolve, MagicDNS is off.
6. If the app asks for a QR and you opened the bare URL, run `./scripts/pair.sh` and use that link. The bare URL is the password form, not the pairing token.
