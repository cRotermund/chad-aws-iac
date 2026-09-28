#!/usr/bin/env bash
set -euo pipefail

# Git Bash can rewrite Unix-looking arguments such as /nginx/tls/... into
# Windows filesystem paths when invoking the native AWS CLI.
export MSYS_NO_PATHCONV=1

certificate_file="${1:-}"
private_key_file="${2:-}"
ca_bundle_file="${3:-}"

if [[ -z "$certificate_file" || -z "$private_key_file" || -z "$ca_bundle_file" || "$certificate_file" == "-h" || "$certificate_file" == "--help" ]]; then
    echo "Usage: $0 <certificate.pem> <private-key.pem> <ca-bundle.pem>" >&2
    echo "Set NGINX_INSTANCE_ID to refresh a live nginx node after upload." >&2
    exit 2
fi

for file in "$certificate_file" "$private_key_file"; do
    if [[ ! -f "$file" ]]; then
        echo "File not found: $file" >&2
        exit 1
    fi
done

if [[ ! -f "$ca_bundle_file" ]]; then
    echo "File not found: $ca_bundle_file" >&2
    exit 1
fi

command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "OpenSSL is required" >&2; exit 1; }

region="${AWS_REGION:-us-east-1}"
certificate_parameter="/nginx/tls/rotorlabs/certificate"
ca_bundle_parameter="/nginx/tls/rotorlabs/ca-bundle"
private_key_parameter="/nginx/tls/rotorlabs/private-key"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

cp "$certificate_file" "$temp_dir/certificate.pem"
cp "$ca_bundle_file" "$temp_dir/ca-bundle.pem"

# Fail before changing SSM if the certificate is malformed, expired, or does
# not match the supplied private key.
openssl x509 -in "$certificate_file" -noout -checkend 0 >/dev/null
certificate_names="$(openssl x509 -in "$certificate_file" -noout -text)"
for domain in apps.rotorlabs.io admin.rotorlabs.io apis.rotorlabs.io; do
    if ! printf '%s\n' "$certificate_names" | grep -Eq "DNS:(${domain//./\\.}|\\*\\.rotorlabs\\.io)"; then
        echo "Certificate does not cover $domain" >&2
        exit 1
    fi
done
certificate_public_key="$(openssl x509 -in "$certificate_file" -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256)"
private_key_public_key="$(openssl pkey -in "$private_key_file" -pubout | openssl pkey -pubin -outform DER | openssl dgst -sha256)"
if [[ "$certificate_public_key" != "$private_key_public_key" ]]; then
    echo "Certificate and private key do not match" >&2
    exit 1
fi

put_parameter() {
    local name="$1"
    local value_file="$2"
    local value
    value="$(cat "$value_file")"
    if (( ${#value} > 8192 )); then
        echo "SSM parameter value exceeds the 8 KiB Advanced tier limit: $name" >&2
        exit 1
    fi
    local args=(ssm put-parameter --region "$region" --name "$name" --type SecureString --tier Intelligent-Tiering --value "$value" --overwrite)

    if [[ -n "${NGINX_TLS_KMS_KEY_ID:-}" ]]; then
        args+=(--key-id "$NGINX_TLS_KMS_KEY_ID")
    fi

    aws "${args[@]}" >/dev/null
}

put_parameter "$certificate_parameter" "$temp_dir/certificate.pem"
put_parameter "$ca_bundle_parameter" "$temp_dir/ca-bundle.pem"
put_parameter "$private_key_parameter" "$private_key_file"
echo "Uploaded certificate, CA bundle, and private key to SSM in $region."

if [[ -z "${NGINX_INSTANCE_ID:-}" ]]; then
    echo "NGINX_INSTANCE_ID is not set; upload complete, but the running node was not reloaded."
    exit 0
fi

managed_node_count="$(aws ssm describe-instance-information \
    --region "$region" \
    --filters "Key=InstanceIds,Values=$NGINX_INSTANCE_ID" \
    --query 'length(InstanceInformationList)' \
    --output text)"
if [[ "$managed_node_count" != "1" ]]; then
    echo "Instance $NGINX_INSTANCE_ID is not registered with Systems Manager in $region." >&2
    echo "Confirm the instance is running, the SSM Agent is online, and the Nginx IAM role has AmazonSSMManagedInstanceCore." >&2
    exit 1
fi

managed_node_ping="$(aws ssm describe-instance-information \
    --region "$region" \
    --filters "Key=InstanceIds,Values=$NGINX_INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text)"
if [[ "$managed_node_ping" != "Online" ]]; then
    echo "Instance $NGINX_INSTANCE_ID is registered with Systems Manager but is not online (status: $managed_node_ping)." >&2
    exit 1
fi

remote_command=$(cat <<EOF
set -euo pipefail
tmp_dir=\$(mktemp -d /tmp/nginx-tls.XXXXXX)
trap 'rm -rf "\$tmp_dir"' EXIT
umask 077
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
aws ssm get-parameter --region '$region' --name '$certificate_parameter' --with-decryption --query 'Parameter.Value' --output text > "\$tmp_dir/certificate.pem"
aws ssm get-parameter --region '$region' --name '$ca_bundle_parameter' --with-decryption --query 'Parameter.Value' --output text > "\$tmp_dir/ca-bundle.pem"
aws ssm get-parameter --region '$region' --name '$private_key_parameter' --with-decryption --query 'Parameter.Value' --output text > "\$tmp_dir/private-key.pem"
install -d -m 700 /etc/nginx/ssl
cat "\$tmp_dir/certificate.pem" "\$tmp_dir/ca-bundle.pem" > "\$tmp_dir/fullchain.pem"
install -m 644 "\$tmp_dir/certificate.pem" /etc/nginx/ssl/rotorlabs.crt
install -m 644 "\$tmp_dir/ca-bundle.pem" /etc/nginx/ssl/rotorlabs.ca-bundle
install -m 644 "\$tmp_dir/fullchain.pem" /etc/nginx/ssl/rotorlabs.fullchain.pem
install -m 600 "\$tmp_dir/private-key.pem" /etc/nginx/ssl/rotorlabs.key
nginx_bin=\$(command -v nginx || true)
if [[ -z "\$nginx_bin" ]]; then
    echo "Nginx is not installed on the target instance" >&2
    exit 1
fi
"\$nginx_bin" -t
systemctl reload nginx
EOF
)

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

remote_parameters="$(printf '{"commands":["%s"]}' "$(json_escape "$remote_command")")"

command_id="$(aws ssm send-command \
    --region "$region" \
    --instance-ids "$NGINX_INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters "$remote_parameters" \
    --query 'Command.CommandId' \
    --output text)"

for _ in {1..30}; do
    status="$(aws ssm get-command-invocation \
        --region "$region" \
        --command-id "$command_id" \
        --instance-id "$NGINX_INSTANCE_ID" \
        --query Status \
        --output text)"

    case "$status" in
        Success)
            echo "Nginx certificate deployed and configuration reloaded."
            exit 0
            ;;
        Failed|Cancelled|TimedOut|Cancelling)
            aws ssm get-command-invocation \
                --region "$region" \
                --command-id "$command_id" \
                --instance-id "$NGINX_INSTANCE_ID" \
                --query '{status:Status,stderr:StandardErrorContent,stdout:StandardOutputContent}' \
                --output yaml >&2
            exit 1
            ;;
    esac
    sleep 2
done

echo "Timed out waiting for the Nginx deployment command: $command_id" >&2
exit 1
