#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Source this script instead: source ./scripts/use-kubeconfig.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! "$SCRIPT_DIR/get-kubeconfig.sh"; then
  return 1
fi

export KUBECONFIG="$ROOT_DIR/kubeconfig.yaml"
echo "KUBECONFIG set to $KUBECONFIG"
