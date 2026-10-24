#!/usr/bin/env bash
set -euo pipefail
# Remove SSH host keys for instances that Terraform rebuilt, so the next connection
# does not fail with "REMOTE HOST IDENTIFICATION HAS CHANGED".
#
# Host IPs come from the stack outputs (terraform output -raw), so this stays in
# step with what was actually deployed. Entries are removed with ssh-keygen -R,
# which also handles hashed known_hosts entries. ssh-keygen keeps a backup at
# known_hosts.old.
#
# Usage:
#   scripts/purge-known-hosts.sh [homelab|game-servers|all] [--dry-run]
#
# Environment:
#   KNOWN_HOSTS_FILE   known_hosts path (default: ~/.ssh/known_hosts)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KNOWN_HOSTS="${KNOWN_HOSTS_FILE:-$HOME/.ssh/known_hosts}"
STACK="all"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    homelab | game-servers | all) STACK="$arg" ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      sed -n '3,15p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "ssh-keygen not found on PATH; install the OpenSSH client first." >&2
  exit 1
fi

IPS=()
LABELS=()

# collect <stack-dir> <output-name>...
collect() {
  local stack_dir="$1"
  shift
  local output value
  for output in "$@"; do
    value="$(cd "$ROOT_DIR/$stack_dir" && terraform output -raw "$output" 2>/dev/null || true)"
    if [ -n "$value" ]; then
      IPS+=("$value")
      LABELS+=("$stack_dir.$output")
      echo "  $stack_dir.$output = $value"
    else
      echo "  warning: $stack_dir.$output is not available (has the stack been applied?)" >&2
    fi
  done
}

echo "Reading host IPs from Terraform outputs..."
if [ "$STACK" = "homelab" ] || [ "$STACK" = "all" ]; then
  collect homelab k3s_server_public_ip k3s_agent_public_ip nginx_public_ip
fi
if [ "$STACK" = "game-servers" ] || [ "$STACK" = "all" ]; then
  collect game-servers satisfactory_public_ip
fi

if [ "${#IPS[@]}" -eq 0 ]; then
  echo "No host IPs found; nothing to purge." >&2
  exit 1
fi

echo
echo "known_hosts: $KNOWN_HOSTS"
if [ ! -f "$KNOWN_HOSTS" ]; then
  echo "No known_hosts file exists; nothing to purge."
  exit 0
fi

REMOVED=0
for i in "${!IPS[@]}"; do
  ip="${IPS[$i]}"
  label="${LABELS[$i]}"
  if ! ssh-keygen -F "$ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
    echo "[skip] $label ($ip): no known_hosts entry"
    continue
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] $label ($ip): would remove its known_hosts entry"
    continue
  fi
  ssh-keygen -R "$ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1
  echo "[removed] $label ($ip)"
  REMOVED=$((REMOVED + 1))
done

echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run: no changes made."
else
  echo "Done. Removed $REMOVED entr$( [ "$REMOVED" -eq 1 ] && echo y || echo ies )."
fi
