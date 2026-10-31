# Docker (optional)

Use this when you want the agent's filesystem isolated from the host.
On macOS and Linux, prefer the native installers: phone QR pairing and the
host's own toolchains depend on them.

```bash
cd docker
export OPENCODE_PASSWORD="$(openssl rand -hex 16)"
export OPENCODE_WORKSPACE="$HOME/work"
docker compose up -d
docker compose logs -f
```

The image tag in `compose.yaml` is a pin (`OPENCODE_IMAGE` overrides it). Match the major version of the clients you connect with.

Phone QR pairing (`opencode pair`) talks to the managed background service on the host, not to a container that was started without `--service`. For the app, prefer the native installers. The container is for a filesystem you want walled off.

Then publish it on the tailnet from the host (the container port is already
bound to loopback):

```bash
tailscale serve --bg --https=443 http://127.0.0.1:49374
```

## Trade-offs

- **Isolation:** the agent sees only the volumes you mount. Good for containing
  blast radius.
- **Toolchains:** the agent executes *inside* the image. It will not find your
  host's node/cargo/python unless they are in the image. Derive an image if you
  need them:

  ```dockerfile
  FROM ghcr.io/anomalyco/opencode:2.0.0
  # Pin the same major version as the CLI you pair from.
  # Override the compose image with OPENCODE_IMAGE.
  USER root
  RUN apt-get update && apt-get install -y git ripgrep build-essential python3 nodejs
  USER opencode
  ```

- **Auth state:** provider credentials live in the `opencode-config` volume.
  Run `docker compose exec opencode opencode auth login` once.
- **Workspace ownership:** mount a directory owned by a UID the container user
  can write to, otherwise the agent cannot edit files.

Verification is the same as the native path: `curl -u opencode:$OPENCODE_PASSWORD
https://<host>.<tailnet>.ts.net/api/info`.
