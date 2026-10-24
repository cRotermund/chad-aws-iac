#!/usr/bin/env bash
set -uo pipefail

# Read-only health check for the game server stack (game-servers/).
# Checks the Satisfactory EC2 instance, its Elastic IP, its security group, and the
# game's documented ports. Does not start, stop, or modify any resource, and does
# not print credentials.
#
# Satisfactory ports (wiki: Dedicated servers, patch 1.1.0.0+):
#   7777/tcp  server traffic and HTTPS API
#   7777/udp  game traffic and query
#   8888/tcp  reliable messaging (without it, players stall on the loading screen)

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR/game-servers" || exit 1

PROFILE="${AWS_PROFILE:-terraform-iac}"
REGION="${AWS_REGION:-us-east-1}"
NET_TIMEOUT="${HEALTHCHECK_NET_TIMEOUT:-5}"
GAME_PORT=7777
RELIABLE_PORT=8888
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

terraform_output() {
  terraform output -raw "$1" 2>/dev/null
}

tcp_open() {
  # $1 host, $2 port. Pure bash TCP connect with a timeout (no extra tools needed).
  timeout "$NET_TIMEOUT" bash -c "exec 3<>/dev/tcp/$1/$2" >/dev/null 2>&1
}

printf 'Game server health check\n'
printf 'Repository: %s\n' "$ROOT_DIR"
printf 'AWS profile: %s\n\n' "$PROFILE"

for command_name in terraform aws curl timeout; do
  if command -v "$command_name" >/dev/null 2>&1; then
    pass_check "$command_name is installed"
  else
    fail_check "$command_name is installed"
  fi
done

INSTANCE_ID="$(terraform_output satisfactory_instance_id || true)"
EXPECTED_IP="$(terraform_output satisfactory_public_ip || true)"
SG_ID="$(terraform_output satisfactory_security_group_id || true)"

if [ -z "$INSTANCE_ID" ] || [ -z "$EXPECTED_IP" ] || [ -z "$SG_ID" ]; then
  fail_check "game-servers stack outputs are available (has the stack been applied?)"
  printf '\nCannot run AWS and network checks without stack outputs.\n'
  printf '\nHealth check completed with %d failure(s).\n' "$failures"
  exit 1
fi
pass_check "game-servers stack outputs are available"

# EC2 instance state
STATE="$(aws --profile "$PROFILE" --region "$REGION" ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || true)"
if [ "$STATE" = "running" ]; then
  pass_check "EC2 instance $INSTANCE_ID is running"
else
  fail_check "EC2 instance $INSTANCE_ID is running (state: ${STATE:-unknown})"
fi

# EC2 system and instance status checks
STATUS="$(aws --profile "$PROFILE" --region "$REGION" ec2 describe-instance-status \
  --instance-ids "$INSTANCE_ID" \
  --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' --output text 2>/dev/null || true)"
if [ "$STATUS" = "$(printf 'ok\tok')" ]; then
  pass_check "EC2 system and instance status checks are OK"
else
  fail_check "EC2 system and instance status checks are OK (status: ${STATUS:-unknown})"
fi

# Elastic IP: the instance's public IP must match the Terraform-owned EIP
ACTUAL_IP="$(aws --profile "$PROFILE" --region "$REGION" ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)"
if [ "$ACTUAL_IP" = "$EXPECTED_IP" ]; then
  pass_check "Instance public IP matches the Elastic IP ($EXPECTED_IP)"
else
  fail_check "Instance public IP matches the Elastic IP (instance: ${ACTUAL_IP:-none}, EIP: $EXPECTED_IP)"
fi

# Security group rules: game port (TCP and UDP) and reliable port (TCP) must be open
SG_RULES="$(aws --profile "$PROFILE" --region "$REGION" ec2 describe-security-groups \
  --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,ToPort]' --output text 2>/dev/null || true)"

rule_open() {
  # $1 protocol, $2 port
  printf '%s\n' "$SG_RULES" | awk -v p="$1" -v n="$2" '$1==p && $2==n && $3==n {found=1} END {exit !found}'
}

for rule in "tcp $GAME_PORT game (TCP)" "udp $GAME_PORT game (UDP)" "tcp $RELIABLE_PORT reliable messaging (TCP)"; do
  set -- $rule
  proto="$1"; port="$2"; label="$3 $4"
  if rule_open "$proto" "$port"; then
    pass_check "Security group allows $proto/$port $label"
  else
    fail_check "Security group allows $proto/$port $label"
  fi
done

# Network reachability on the public IP
if [ -n "$EXPECTED_IP" ]; then
  if tcp_open "$EXPECTED_IP" "$GAME_PORT"; then
    pass_check "TCP $GAME_PORT is reachable on $EXPECTED_IP"
  else
    fail_check "TCP $GAME_PORT is reachable on $EXPECTED_IP"
  fi

  if tcp_open "$EXPECTED_IP" "$RELIABLE_PORT"; then
    pass_check "TCP $RELIABLE_PORT (reliable messaging) is reachable on $EXPECTED_IP"
  else
    fail_check "TCP $RELIABLE_PORT (reliable messaging) is reachable on $EXPECTED_IP"
  fi

  # Documented liveness signal: the HTTPS API answers unauthenticated requests on 7777/tcp
  # with route_handler_not_found when the server is up.
  api_body="$(curl --silent --insecure --max-time "$NET_TIMEOUT" "https://$EXPECTED_IP:$GAME_PORT/" 2>/dev/null || true)"
  if printf '%s' "$api_body" | grep -q 'route_handler_not_found'; then
    pass_check "Satisfactory HTTPS API responds on $EXPECTED_IP:$GAME_PORT"
  else
    fail_check "Satisfactory HTTPS API responds on $EXPECTED_IP:$GAME_PORT (no expected response)"
  fi
fi

# UDP cannot be verified reliably from a shell without a game client; report explicitly.
skip_check "UDP $GAME_PORT reachability (not verifiable from bash without a game client)"

printf '\nHealth check completed with %d failure(s).\n' "$failures"
[ "$failures" -eq 0 ]
