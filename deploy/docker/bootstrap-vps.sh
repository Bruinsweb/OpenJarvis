#!/usr/bin/env bash
# Provision the official Docker Engine and launch the private OpenJarvis stack.
# Run on a fresh Ubuntu VPS from this fork:
#   bash deploy/docker/bootstrap-vps.sh
#
# Does NOT configure SSH accounts, firewall, external access, or a public domain.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
umask 077

if [[ ! -r /etc/os-release ]]; then
  echo "Unsupported OS: missing /etc/os-release" >&2
  exit 1
fi
# shellcheck source=/dev/null
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
  echo "Use Ubuntu 24.04 LTS. Detected: ${PRETTY_NAME:-unknown}." >&2
  exit 1
fi

if (( EUID == 0 )); then
  sudo_cmd=()
else
  command -v sudo >/dev/null || { echo "sudo required"; exit 1; }
  sudo_cmd=(sudo)
fi

echo "[1/5] Checking/installing Docker Engine + Compose"
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  "${sudo_cmd[@]}" apt-get update
  "${sudo_cmd[@]}" apt-get install -y ca-certificates curl git openssl
  "${sudo_cmd[@]}" install -m 0755 -d /etc/apt/keyrings
  "${sudo_cmd[@]}" curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  "${sudo_cmd[@]}" chmod a+r /etc/apt/keyrings/docker.asc
  ubuntu_codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-noble}}"
  arch="$(dpkg --print-architecture)"
  printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' "$ubuntu_codename" "$arch" |
    "${sudo_cmd[@]}" tee /etc/apt/sources.list.d/docker.sources >/dev/null
  "${sudo_cmd[@]}" apt-get update
  "${sudo_cmd[@]}" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
"${sudo_cmd[@]}" systemctl enable --now docker

echo "[2/5] Configuring secret only on this VPS"
if [[ ! -f .env ]]; then
  command -v openssl >/dev/null || { echo "openssl missing"; exit 1; }
  printf 'OPENJARVIS_API_KEY=oj_sk_%s\nCOMPOSE_PROJECT_NAME=openjarvis\n' "$(openssl rand -hex 32)" > .env
fi
chmod 600 .env
if ! grep -Eq '^OPENJARVIS_API_KEY=oj_sk_[[:alnum:]]+' .env; then
  echo "Set a valid OPENJARVIS_API_KEY in deploy/docker/.env" >&2
  exit 1
fi

echo "[3/5] Validating and starting the protected stack"
"${sudo_cmd[@]}" docker compose -f docker-compose.vps.yml config --quiet
"${sudo_cmd[@]}" docker compose -f docker-compose.vps.yml up -d --build

echo "[4/5] Downloading the small starter model (CPU-compatible)"
"${sudo_cmd[@]}" docker compose -f docker-compose.vps.yml exec -T ollama ollama pull qwen3.5:2b
"${sudo_cmd[@]}" docker compose -f docker-compose.vps.yml restart jarvis

echo "[5/5] Testing the local health endpoint"
healthy=0
for _ in {1..30}; do
  if curl -fsS --max-time 5 http://127.0.0.1:8000/health; then
    healthy=1
    break
  fi
  sleep 3
done
echo
"${sudo_cmd[@]}" docker compose -f docker-compose.vps.yml ps
if (( healthy != 1 )); then
  echo "Health test failed. Inspect logs: sudo docker compose -f docker-compose.vps.yml logs --tail=100 jarvis" >&2
  exit 1
fi

echo "OpenJarvis responds on VPS loopback 127.0.0.1:8000."
echo "Next: SSH-forward TCP 8000 from your own computer (see README-VPS.md)."
echo "The external firewall, SSH hardening, backups, and scheduled agents still need setup."
