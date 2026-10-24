#!/usr/bin/env bash
set -euo pipefail
# SSH into the Satisfactory game server (Debian; default user is "admin").
# Uses the game-servers key pair. The private key lives in ~/.ssh and is never committed.
# Override with GAME_SERVER_KEY_FILE or GAME_SERVER_SSH_USER if needed.
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR/game-servers"

SERVER_IP="$(terraform output -raw satisfactory_public_ip)"
KEY_FILE="${GAME_SERVER_KEY_FILE:-${HOME}/.ssh/game-servers-ed25519}"
SSH_USER="${GAME_SERVER_SSH_USER:-admin}"

echo "Connecting to game server at $SERVER_IP as $SSH_USER..."
ssh -i "$KEY_FILE" "$SSH_USER@$SERVER_IP" "$@"
