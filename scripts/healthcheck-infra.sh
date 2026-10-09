#!/usr/bin/env bash
set -uo pipefail

# Read-only infrastructure health check for the k3s, ArgoCD, and nginx stack.
# This script intentionally does not retrieve or print credentials or secrets.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROFILE="${AWS_PROFILE:-terraform-iac}"
HTTP_TIMEOUT="${HEALTHCHECK_HTTP_TIMEOUT:-10}"
KUBECTL_TIMEOUT="${HEALTHCHECK_KUBECTL_TIMEOUT:-5s}"
KUBECONFIG_FILE="${KUBECONFIG:-$ROOT_DIR/kubeconfig.yaml}"
failures=0

pass_check() {
  printf '[PASS] %s\n' "$1"
}

fail_check() {
  printf '[FAIL] %s\n' "$1"
  failures=$((failures + 1))
}

skip_check() {
  printf '[SKIP] %s\n' "$1"
}

require_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    pass_check "$command_name is installed"
    return 0
  fi

  fail_check "$command_name is installed"
  return 1
}

terraform_output() {
  terraform output -raw "$1" 2>/dev/null
}

http_status() {
  curl --silent --show-error --max-time "$HTTP_TIMEOUT" \
    --output /dev/null --write-out '%{http_code}' "$1" 2>/dev/null
}

check_http_route() {
  local name="$1"
  local url="$2"
  local status

  if ! status="$(http_status "$url")"; then
    fail_check "$name ($url) is reachable"
    return
  fi

  case "$status" in
    2??|3??|4??)
      pass_check "$name ($url) returned HTTP $status"
      ;;
    *)
      fail_check "$name ($url) returned HTTP ${status:-no response}"
      ;;
  esac
}

check_oidc_discovery() {
  local url='https://apis.rotorlabs.io/aws-oidc/.well-known/openid-configuration'
  local response

  if ! response="$(curl --fail --silent --show-error --max-time "$HTTP_TIMEOUT" "$url" 2>/dev/null)"; then
    fail_check 'OIDC discovery endpoint is reachable'
    return
  fi

  if printf '%s' "$response" | grep -Eq '"issuer"[[:space:]]*:[[:space:]]*"https://apis\.rotorlabs\.io/aws-oidc"' && \
    printf '%s' "$response" | grep -Eq '"jwks_uri"[[:space:]]*:[[:space:]]*"https://apis\.rotorlabs\.io/aws-oidc/openid/v1/jwks"'; then
    pass_check 'OIDC discovery document has the expected issuer and JWKS URL'
  else
    fail_check 'OIDC discovery document has the expected issuer and JWKS URL'
  fi
}

check_oidc_jwks() {
  local url='https://apis.rotorlabs.io/aws-oidc/openid/v1/jwks'
  local response

  if ! response="$(curl --fail --silent --show-error --max-time "$HTTP_TIMEOUT" "$url" 2>/dev/null)"; then
    fail_check 'OIDC JWKS endpoint is reachable'
    return
  fi

  if printf '%s' "$response" | grep -Eq '"keys"[[:space:]]*:[[:space:]]*\[[^]]+\]'; then
    pass_check 'OIDC JWKS response contains public keys'
  else
    fail_check 'OIDC JWKS response contains public keys'
  fi
}

printf 'Infrastructure health check\n'
printf 'Repository: %s\n' "$ROOT_DIR"
printf 'AWS profile: %s\n' "$PROFILE"
printf 'Kubeconfig: %s\n\n' "$KUBECONFIG_FILE"

for command_name in terraform aws kubectl curl grep awk tr; do
  require_command "$command_name" || true
done

REGION=''
SERVER_ID=''
AGENT_ID=''
NGINX_ID=''
if command -v terraform >/dev/null 2>&1; then
  if ! REGION="$(terraform_output aws_region)" || [ -z "$REGION" ]; then
    fail_check 'Terraform exposes the AWS region'
  else
    pass_check "Terraform exposes AWS region $REGION"
  fi

  if ! SERVER_ID="$(terraform_output k3s_server_instance_id)" || [ -z "$SERVER_ID" ]; then
    fail_check 'Terraform exposes the k3s server instance ID'
  fi

  if ! AGENT_ID="$(terraform_output k3s_agent_instance_id)" || [ -z "$AGENT_ID" ]; then
    fail_check 'Terraform exposes the k3s agent instance ID'
  fi

  if ! NGINX_ID="$(terraform_output nginx_instance_id)" || [ -z "$NGINX_ID" ]; then
    fail_check 'Terraform exposes the nginx instance ID'
  fi
else
  skip_check 'Terraform output checks (terraform is not installed)'
fi

if [ -n "$REGION" ] && [ -n "$SERVER_ID" ] && [ -n "$AGENT_ID" ] && [ -n "$NGINX_ID" ] && command -v aws >/dev/null 2>&1; then
  INSTANCE_IDS=("$SERVER_ID" "$AGENT_ID" "$NGINX_ID")
  instance_rows="$(aws --profile "$PROFILE" --region "$REGION" ec2 describe-instances \
    --instance-ids "${INSTANCE_IDS[@]}" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text 2>/dev/null | tr -d '\r')"

  if [ -z "$instance_rows" ]; then
    fail_check 'AWS reports the k3s and nginx instances'
  else
    stopped_instances=0
    while IFS=$'\t' read -r instance_id state; do
      if [ "$state" = 'running' ]; then
        pass_check "EC2 instance $instance_id is running"
      else
        fail_check "EC2 instance $instance_id is running (state: ${state:-unknown})"
        stopped_instances=$((stopped_instances + 1))
      fi
    done <<< "$instance_rows"

    status_rows="$(aws --profile "$PROFILE" --region "$REGION" ec2 describe-instance-status \
      --instance-ids "${INSTANCE_IDS[@]}" --include-all-instances \
      --query 'InstanceStatuses[].[InstanceId,SystemStatus.Status,InstanceStatus.Status]' --output text 2>/dev/null | tr -d '\r')"
    if [ -n "$status_rows" ] && [ "$stopped_instances" -eq 0 ] && \
      printf '%s\n' "$status_rows" | awk 'NF < 3 || $2 != "ok" || $3 != "ok" { failed = 1 } END { exit failed }'; then
      pass_check 'EC2 system and instance status checks are OK'
    else
      fail_check 'EC2 system and instance status checks are OK'
    fi
  fi
else
  skip_check 'EC2 instance state and status checks (Terraform outputs or AWS CLI unavailable)'
fi

if ! command -v kubectl >/dev/null 2>&1; then
  skip_check 'Kubernetes API, node, and ArgoCD checks (kubectl is not installed)'
elif [ ! -f "$KUBECONFIG_FILE" ]; then
  fail_check "Kubeconfig exists at $KUBECONFIG_FILE"
  skip_check 'Kubernetes API, node, and ArgoCD checks (kubeconfig is unavailable)'
else
  pass_check "Kubeconfig exists at $KUBECONFIG_FILE"

  if api_response="$(kubectl --kubeconfig "$KUBECONFIG_FILE" \
    --request-timeout="$KUBECTL_TIMEOUT" get nodes --no-headers 2>&1)"; then
    pass_check 'Kubernetes API is serving authenticated resource requests'
  else
    api_summary="$(printf '%s' "$api_response" | tr '\r\n' '  ')"
    fail_check "Kubernetes API is serving authenticated resource requests: ${api_summary:0:240}"
  fi

  if readyz_response="$(kubectl --kubeconfig "$KUBECONFIG_FILE" \
    --request-timeout="$KUBECTL_TIMEOUT" get --raw='/readyz?verbose' 2>&1)" && \
    printf '%s' "$readyz_response" | grep 'readyz check passed' >/dev/null; then
    pass_check 'Kubernetes API reports ready (/readyz?verbose)'
  else
    readyz_summary="$(printf '%s' "$readyz_response" | tr '\r\n' '  ')"
    fail_check "Kubernetes API reports ready (/readyz?verbose): ${readyz_summary:0:240}"
  fi

  node_status="$(printf '%s' "$api_response" | tr -d '\r')"
  if [ -n "$node_status" ] && printf '%s\n' "$node_status" | awk 'NF < 2 || $2 !~ /^Ready$/ { failed = 1 } END { exit failed }'; then
    pass_check 'All Kubernetes nodes report Ready'
  else
    fail_check 'All Kubernetes nodes report Ready'
  fi

  available_replicas="$(kubectl --kubeconfig "$KUBECONFIG_FILE" --request-timeout="$KUBECTL_TIMEOUT" \
    --namespace argocd get deployment argocd-server \
    --output jsonpath='{.status.availableReplicas}' 2>/dev/null)"
  if [ "${available_replicas:-0}" -ge 1 ] 2>/dev/null; then
    pass_check 'ArgoCD server deployment has an available replica'
  else
    fail_check 'ArgoCD server deployment has an available replica'
  fi
fi

if command -v curl >/dev/null 2>&1; then
  check_http_route 'ArgoCD HTTPS endpoint' 'https://admin.rotorlabs.io/argocd/'
  check_http_route 'Applications HTTPS endpoint' 'https://apps.rotorlabs.io/'
  check_http_route 'APIs HTTPS endpoint' 'https://apis.rotorlabs.io/'
  check_oidc_discovery
  check_oidc_jwks
else
  skip_check 'Public HTTPS and OIDC endpoint checks (curl is not installed)'
fi

printf '\nHealth check completed with %s failure(s).\n' "$failures"
if [ "$failures" -eq 0 ]; then
  exit 0
fi
exit 1
