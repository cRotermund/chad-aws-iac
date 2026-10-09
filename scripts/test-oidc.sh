#!/usr/bin/env bash
set -uo pipefail

# Exercise K3s-to-AWS web-identity federation and clean up temporary resources.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROFILE="${AWS_PROFILE:-terraform-iac}"
KUBECONFIG_FILE="${KUBECONFIG:-$ROOT_DIR/kubeconfig.yaml}"
NAMESPACE="default"
TEST_SERVICE_ACCOUNT="aws-test"
OTHER_SERVICE_ACCOUNT="aws-oidc-test-other-$$"
TEMP_DIR="$(mktemp -d)"
TEST_TOKEN="$TEMP_DIR/test.jwt"
OTHER_TOKEN="$TEMP_DIR/other.jwt"
WRONG_AUDIENCE_TOKEN="$TEMP_DIR/wrong-audience.jwt"
TEST_SERVICE_ACCOUNT_CREATED=0
OTHER_SERVICE_ACCOUNT_CREATED=0
AWS_ACCESS_KEY_ID_ASSUMED=''
AWS_SECRET_ACCESS_KEY_ASSUMED=''
AWS_SESSION_TOKEN_ASSUMED=''
failures=0

cleanup() {
  if [ "$TEST_SERVICE_ACCOUNT_CREATED" -eq 1 ]; then
    kubectl --kubeconfig "$KUBECONFIG_FILE" --namespace "$NAMESPACE" \
      delete serviceaccount "$TEST_SERVICE_ACCOUNT" --ignore-not-found >/dev/null 2>&1 || true
  fi

  if [ "$OTHER_SERVICE_ACCOUNT_CREATED" -eq 1 ]; then
    kubectl --kubeconfig "$KUBECONFIG_FILE" --namespace "$NAMESPACE" \
      delete serviceaccount "$OTHER_SERVICE_ACCOUNT" --ignore-not-found >/dev/null 2>&1 || true
  fi

  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

pass_check() {
  printf '[PASS] %s\n' "$1"
}

fail_check() {
  printf '[FAIL] %s\n' "$1"
  failures=$((failures + 1))
}

require_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi

  fail_check "$command_name is installed"
  return 1
}

terraform_output() {
  terraform output -raw "$1" 2>/dev/null
}

assumed_aws() {
  env -u AWS_PROFILE \
    AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID_ASSUMED" \
    AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY_ASSUMED" \
    AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN_ASSUMED" \
    aws --region "$REGION" --no-cli-pager "$@"
}

token_file_uri() {
  local token_file="$1"

  if command -v cygpath >/dev/null 2>&1; then
    printf 'file://%s' "$(cygpath --mixed "$token_file")"
  else
    printf 'file://%s' "$token_file"
  fi
}

create_service_account_if_needed() {
  local service_account="$1"
  local created_variable="$2"

  if kubectl --kubeconfig "$KUBECONFIG_FILE" --namespace "$NAMESPACE" \
    get serviceaccount "$service_account" >/dev/null 2>&1; then
    pass_check "Kubernetes service account $NAMESPACE/$service_account exists"
    return 0
  fi

  if kubectl --kubeconfig "$KUBECONFIG_FILE" --namespace "$NAMESPACE" \
    create serviceaccount "$service_account" >/dev/null; then
    printf -v "$created_variable" '%s' 1
    pass_check "Created Kubernetes service account $NAMESPACE/$service_account"
    return 0
  fi

  fail_check "Created Kubernetes service account $NAMESPACE/$service_account"
  return 1
}

assume_role() {
  local token_file="$1"
  local session_name="$2"
  local error_file="$TEMP_DIR/assume-role.error"
  local output

  output="$(aws --profile "$PROFILE" --region "$REGION" --no-cli-pager \
    sts assume-role-with-web-identity \
    --role-arn "$ROLE_ARN" \
    --role-session-name "$session_name" \
    --web-identity-token "$(token_file_uri "$token_file")" \
    --query '[AssumedRoleUser.Arn,Credentials.AccessKeyId,Credentials.SecretAccessKey,Credentials.SessionToken]' \
    --output text 2>"$error_file")" || {
    if [ "$session_name" = 'positive-oidc-test' ] && [ -s "$error_file" ]; then
      printf '%s\n' 'STS rejected the trusted service-account token:' >&2
      sed 's/[[:space:]]\+$//' "$error_file" >&2
    fi
    return 1
  }

  read -r ASSUMED_ROLE_ARN AWS_ACCESS_KEY_ID_ASSUMED \
    AWS_SECRET_ACCESS_KEY_ASSUMED AWS_SESSION_TOKEN_ASSUMED <<< "$output"
  [ -n "${ASSUMED_ROLE_ARN:-}" ] && [ -n "${AWS_ACCESS_KEY_ID_ASSUMED:-}" ]
}

printf 'K3s OIDC federation test\n'
printf 'Repository: %s\n' "$ROOT_DIR"
printf 'AWS profile: %s\n' "$PROFILE"
printf 'Kubeconfig: %s\n\n' "$KUBECONFIG_FILE"

for command_name in aws kubectl terraform; do
  require_command "$command_name" || true
done

if [ "$failures" -ne 0 ]; then
  exit 1
fi

REGION="$(terraform_output aws_region)"
ROLE_ARN="$(terraform_output k3s_oidc_test_role_arn)"
PROVIDER_ARN="$(terraform_output k3s_oidc_provider_arn)"

if [ -z "$REGION" ] || [ -z "$ROLE_ARN" ] || [ -z "$PROVIDER_ARN" ]; then
  fail_check 'Terraform exposes the AWS region, OIDC provider ARN, and test role ARN'
  exit 1
fi
pass_check "Terraform exposes test role $ROLE_ARN"

if aws --profile "$PROFILE" --region "$REGION" --no-cli-pager \
  iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
  pass_check 'AWS IAM OIDC provider exists'
else
  fail_check 'AWS IAM OIDC provider exists'
  exit 1
fi

if ! kubectl --kubeconfig "$KUBECONFIG_FILE" --namespace "$NAMESPACE" \
  get namespace "$NAMESPACE" >/dev/null 2>&1; then
  fail_check "Kubernetes namespace $NAMESPACE is accessible"
  exit 1
fi
pass_check "Kubernetes namespace $NAMESPACE is accessible"

create_service_account_if_needed "$TEST_SERVICE_ACCOUNT" TEST_SERVICE_ACCOUNT_CREATED || exit 1
create_service_account_if_needed "$OTHER_SERVICE_ACCOUNT" OTHER_SERVICE_ACCOUNT_CREATED || exit 1

if kubectl --kubeconfig "$KUBECONFIG_FILE" --namespace "$NAMESPACE" \
  create token "$TEST_SERVICE_ACCOUNT" --audience sts.amazonaws.com --duration 1h > "$TEST_TOKEN"; then
  pass_check 'Created token with audience sts.amazonaws.com for the trusted service account'
else
  fail_check 'Created token with audience sts.amazonaws.com for the trusted service account'
  exit 1
fi

if assume_role "$TEST_TOKEN" positive-oidc-test; then
  pass_check 'Trusted service account assumed the IAM role'
else
  fail_check 'Trusted service account assumed the IAM role'
  exit 1
fi

if caller_identity="$(assumed_aws sts get-caller-identity --query Arn --output text 2>/dev/null)" && \
  [ "$caller_identity" = "$ASSUMED_ROLE_ARN" ]; then
  pass_check "STS caller identity is $caller_identity"
else
  fail_check 'STS caller identity matches the assumed IAM role'
fi

if assumed_aws s3api list-buckets --output json >/dev/null 2>&1; then
  fail_check 'Federated role has no unintended S3 access'
else
  pass_check 'Federated role has no unintended S3 access'
fi

if kubectl --kubeconfig "$KUBECONFIG_FILE" --namespace "$NAMESPACE" \
  create token "$OTHER_SERVICE_ACCOUNT" --audience sts.amazonaws.com --duration 1h > "$OTHER_TOKEN"; then
  if assume_role "$OTHER_TOKEN" wrong-subject-test; then
    fail_check 'Different service account was denied by the IAM trust policy'
  else
    pass_check 'Different service account was denied by the IAM trust policy'
  fi
else
  fail_check 'Created token for the negative subject test'
fi

if kubectl --kubeconfig "$KUBECONFIG_FILE" --namespace "$NAMESPACE" \
  create token "$TEST_SERVICE_ACCOUNT" --audience wrong-audience --duration 1h > "$WRONG_AUDIENCE_TOKEN"; then
  if assume_role "$WRONG_AUDIENCE_TOKEN" wrong-audience-test; then
    fail_check 'Wrong token audience was denied by the IAM trust policy'
  else
    pass_check 'Wrong token audience was denied by the IAM trust policy'
  fi
else
  fail_check 'Created token for the negative audience test'
fi

printf '\nOIDC test completed with %s failure(s).\n' "$failures"
if [ "$failures" -eq 0 ]; then
  exit 0
fi
exit 1
