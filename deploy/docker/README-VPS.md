# OpenJarvis on a VPS (private-first)

This guide deploys **the real OpenJarvis source in this repository**, not the
unrelated `AnonymousCoderArtist/JARVIS-2.0` project. It reuses the
upstream multi-stage Dockerfile and API-key authentication.

The initial deployment intentionally uses the **simple** agent. It is a
working baseline for the web UI, chat API and local model, **not** a
fully autonomous JARVIS 4.0 configuration. Enable privileged tools or scheduled
agents only after testing approvals, storage, audit and access policies.

## Prerequisites

- An Ubuntu/Debian Linux VPS with Docker Engine and Docker Compose v2 installed.
- Git, OpenSSL, disk space for the image and model and enough RAM for local inference.
- SSH access. You do **not** need to open TCP 8000 or 11434 in the firewall.
- GPU is optional; on a CPU-only VPS, local generation can be very slow.
  The 2B model below is a small first-test model, not a strong autonomous coder.

A source build compiles the Rust extension and builds the React frontend, so
allow substantial disk/RAM/headroom. Do not copy an existing OpenJarvis .env,
API key, token or other credentials into Git.

## 1. Clone the fork and create a local key

```bash
git clone https://github.com/Bruinsweb/OpenJarvis.git
cd OpenJarvis
# Until PR #1 is reviewed and merged, use the deployment branch:
git switch feature/secure-vps-deployment
cd deploy/docker
umask 077
printf 'OPENJARVIS_API_KEY=oj_sk_%s\nCOMPOSE_PROJECT_NAME=openjarvis\n' "$(openssl rand -hex 32)" > .env
chmod 600 .env
```

The `.env` file is ignored by Git. Store a backup of the key in a password
manager. Never paste it into a repository, issue, public log or chat.

## 2. Validate and start

```bash
docker compose -f docker-compose.vps.yml config --quiet
docker compose -f docker-compose.vps.yml up -d --build
docker compose -f docker-compose.vps.yml ps
```

The application is published on **127.0.0.1:8000 only** on the VPS.
Ollama has **no host port**. The Compose deployment persists OpenJarvis state
under the `jarvis-state` named volume and Ollama models under
`ollama-models`. Both survive container restarts and recreations.

## 3. Download the initial local model

```bash
docker compose -f docker-compose.vps.yml exec ollama ollama pull qwen3.5:2b
docker compose -f docker-compose.vps.yml restart jarvis
curl -fsS http://127.0.0.1:8000/health
docker compose -f docker-compose.vps.yml logs --tail=80 jarvis
```

Model names/availability are controlled by Ollama; if this tag is unavailable,
choose a compatible Ollama model and adjust `--model` in the VPS Compose file
before restarting the app. The /health endpoint reports server/engine readiness. It does **not** prove
that chat, tool approvals or autonomous agent runs work end-to-end.
Docker's healthcheck records health status but an unhealthy container is
**not** automatically restarted by Docker Compose; configure external
monitoring/alerts and test recovery.

## 4. Open JARVIS privately from a laptop

On your **own laptop** (not inside the VPS SSH session):

```bash
ssh -N -L 8000:127.0.0.1:8000 VPS_USER@VPS_HOST
```

Open <http://127.0.0.1:8000> in the laptop browser. Where the UI asks for
credentials, enter your `OPENJARVIS_API_KEY` locally. Do not put the API key
in the URL. The SSH tunnel protects access to the browser UI and HTTP API.

For iPhone access, use a private VPN such as Tailscale with firewall rules and
an authentication layer; do not change the Compose binding to `0.0.0.0` just
to reach the app from the public internet. Design the mobile access path
separately; this guide does not deploy Tailscale or public TLS.

## Operations

```bash
# Inspect deployment
docker compose -f docker-compose.vps.yml ps
docker compose -f docker-compose.vps.yml logs -f --tail=100 jarvis

# Restart app without deleting memory
docker compose -f docker-compose.vps.yml restart jarvis

# Shut down containers (preserves volumes)
docker compose -f docker-compose.vps.yml down

# Update after reviewing changes on the branch
git pull --ff-only
docker compose -f docker-compose.vps.yml up -d --build
```

**Never run `docker compose down -v`** unless you intentionally want to
delete saved JARVIS state and downloaded models. Back up the named volumes
before VPS migrations or upgrades, and test restore procedures. Container
images and API-key scopes should be updated deliberately.

## Safety and limitations

- The VPS Compose file is separate from upstream
  `deploy/docker/docker-compose.yml`, which publishes host ports to all
  interfaces. Use **only** `docker-compose.vps.yml` on the VPS.
- The application requires an API key even though its host port is loopback.
  The upstream service listens inside Docker on 0.0.0.0 so the bridge works;
  that is **not** the host's public interface.
- External code, GitHub repositories, webpages and email may contain prompt
  injection. The agent must not be granted uncontrolled shell, wallet,
  payment, production deployment or email-sending privileges.
- The upstream API-key implementation and approval rules are not a full
  security audit. Keep this build accessible only to trusted operators.
- Free local inference avoids per-call API charges but does not eliminate
  VPS/electricity costs. For fast, capable agents on CPU-only hardware, a
  hosted model may be better, with separate usage charges.
- There is no automatic deployment pipeline and no production uptime claim
  until a real VPS has been connected and smoke-tested.

## Next milestones (not implemented by this Compose file)

1. Verified web UI + authenticated chat against the pulled model.
2. Configurable tool permissions with explicit human approvals.
3. Individual GitHub, Gmail and calendar integrations using least privilege.
4. Durable scheduled jobs and logs; monitoring and backups.
5. A polished multi-agent JARVIS 4.0 dashboard and safe worker isolation.

### Scheduler caveat

The managed-agent scheduler initialized by `jarvis serve` (with the default
`agent_manager.enabled = true`) can execute configured cron/interval agents.
Before relying on it, create a harmless scheduled agent and verify a real
run and audit log. The **separate** command `jarvis scheduler start` currently
constructs `TaskScheduler(store)` without an execution system in the
upstream CLI, so it logs **dry runs** rather than executing model requests.
Do not rely on that command for autonomous work without patching and testing
it. The VPS deployment intentionally does not add a second scheduler process.
