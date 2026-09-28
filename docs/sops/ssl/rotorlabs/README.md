# SSL Certificate Management for rotorlabs

This directory contains scripts and templates for generating certificates for the rotorlabs domains through Namecheap.

## Overview

This SOP covers:

- Generating private keys and Certificate Signing Requests (CSRs)
- Submitting CSRs to Namecheap for certificate issuance
- Validating certificates and private keys
- Deploying certificates to the Nginx ingress node through SSM Parameter Store
- Rotating and, if necessary, rolling back deployed certificates

**IMPORTANT:** Never commit actual certificates, private keys, or CSRs to this repository. Only configuration, scripts, and documentation are version controlled.

## Files

- `README.md` - This SOP
- `rotorlabs.cnf` - OpenSSL configuration for CSR generation
- `generate-csr.sh` - Script to generate a private key and CSR
- `.gitignore` - Ensures local certificate material is not committed
- `../../../scripts/rotate-nginx-tls.sh` - Validates and deploys certificate material to SSM and Nginx

## Generation and Validation

### Generate a private key and CSR

Run the CSR generation script from this directory:

```bash
cd docs/sops/ssl/rotorlabs
./generate-csr.sh
```

This creates local files that must remain private:

- `rotorlabs.key` - Private key
- `rotorlabs.csr` - Certificate Signing Request
- `rotorlabs.cnf` - OpenSSL configuration used during generation

### Submit the CSR to Namecheap

1. Log into the Namecheap account.
2. Navigate to **SSL Certificates** and select **Manage**.
3. Select **Activate** for the purchased certificate.
4. Paste the contents of `rotorlabs.csr` into the CSR field.
5. Select **nginx** as the server type.
6. Complete domain validation using the selected email, DNS, or HTTP method.

The issued certificate must cover all three production hostnames:

- `apps.rotorlabs.io`
- `admin.rotorlabs.io`
- `apis.rotorlabs.io`

A SAN certificate containing all three names or a wildcard certificate covering them is supported.

### Download the issued certificate

Namecheap typically provides:

- `rotorlabs.io.crt` - Server certificate
- `rotorlabs.io.ca-bundle` - Intermediate CA certificates

Keep these files outside the repository until deployment. The server certificate and CA bundle will be combined into the full chain during deployment.

### Validate the CSR and certificate

Validate the CSR:

```bash
openssl req -text -noout -verify -in rotorlabs.csr
```

Inspect the issued certificate and confirm its subject, issuer, expiry, and SANs:

```bash
openssl x509 -text -noout -in rotorlabs.io.crt
```

Check that the certificate matches the private key. The deployment script performs an equivalent public-key check automatically:

```bash
openssl x509 -in rotorlabs.io.crt -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256

openssl pkey -in rotorlabs.key -pubout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256
```

The two hashes must match.

## Deployment

### Initial deployment

The deployment script stores the certificate material in these SSM SecureString parameters:

- `/nginx/tls/rotorlabs/certificate`
- `/nginx/tls/rotorlabs/ca-bundle`
- `/nginx/tls/rotorlabs/private-key`

The certificate and CA bundle are stored separately because their combined value can exceed the 8 KiB Advanced tier limit. The script uses SSM Intelligent-Tiering for each value, allowing AWS to select Advanced tier only when an individual value exceeds the 4 KiB Standard tier limit. Advanced parameters may incur additional Parameter Store charges and support values up to 8 KiB.

Run the script from the repository root without `NGINX_INSTANCE_ID` first. This validates the material and stages the server certificate, CA bundle, and private key in SSM before Terraform creates or replaces the Nginx instance:

```bash
export AWS_REGION=us-east-1
# Required when running the native AWS CLI from Git Bash on Windows.
export MSYS_NO_PATHCONV=1

./scripts/rotate-nginx-tls.sh \
  docs/sops/ssl/rotorlabs/rotorlabs.io.crt \
  docs/sops/ssl/rotorlabs/rotorlabs.key \
  docs/sops/ssl/rotorlabs/rotorlabs.io.ca-bundle
```

Apply the Terraform changes so the Nginx instance has its SSM IAM permissions and TLS configuration:

```bash
terraform apply
```

After Terraform completes and the Nginx instance is online in Systems Manager, run the script again with `NGINX_INSTANCE_ID` set. This fetches the staged values on the instance, validates the Nginx configuration, and reloads Nginx:

```bash
export NGINX_INSTANCE_ID="$(terraform output -raw nginx_instance_id)"

./scripts/rotate-nginx-tls.sh \
  docs/sops/ssl/rotorlabs/rotorlabs.io.crt \
  docs/sops/ssl/rotorlabs/rotorlabs.key \
  docs/sops/ssl/rotorlabs/rotorlabs.io.ca-bundle
```

The script performs these checks before changing SSM:

1. The certificate is parseable and not expired.
2. The certificate covers all three production hostnames or `*.rotorlabs.io`.
3. The certificate public key matches the supplied private key.
4. The certificate and CA bundle are uploaded separately; Nginx concatenates them into the full chain on the instance.

The live deployment then:

1. Fetches the new values from SSM on the Nginx instance.
2. Installs the certificate and private key with restrictive permissions.
3. Runs `nginx -t`.
4. Reloads Nginx without replacing or rebooting the EC2 instance.

If a customer-managed KMS key is used for the SSM parameters, export its key ID or ARN before running the script and configure the matching Terraform variable:

```bash
export NGINX_TLS_KMS_KEY_ID="<kms-key-id-or-arn>"
```

```hcl
nginx_tls_kms_key_arn = "<kms-key-arn>"
```

To upload the values without refreshing Nginx, omit `NGINX_INSTANCE_ID`. The running Nginx process will continue using its current certificate until the node is refreshed.

### Verify the deployment

Check each public endpoint:

```bash
curl -vI https://apps.rotorlabs.io
curl -vI https://admin.rotorlabs.io/argocd
curl -vI https://apis.rotorlabs.io
```

Inspect the certificate served for each hostname:

```bash
openssl s_client -connect apps.rotorlabs.io:443 -servername apps.rotorlabs.io < /dev/null \
  | openssl x509 -noout -subject -issuer -dates
openssl s_client -connect admin.rotorlabs.io:443 -servername admin.rotorlabs.io < /dev/null \
  | openssl x509 -noout -subject -issuer -dates
openssl s_client -connect apis.rotorlabs.io:443 -servername apis.rotorlabs.io < /dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

## Renewal

### Renew and rotate the certificate

Certificates typically last one year. Start renewal at least 30 days before expiration.

1. Generate a new CSR, reusing the existing key only if that is an intentional choice.
2. Complete renewal and domain validation through Namecheap.
3. Download the new server certificate and CA bundle.
4. Run the same deployment script used for initial deployment:

```bash
export AWS_REGION=us-east-1
export NGINX_INSTANCE_ID="$(terraform output -raw nginx_instance_id)"

./scripts/rotate-nginx-tls.sh \
  docs/sops/ssl/rotorlabs/rotorlabs.io.crt \
  docs/sops/ssl/rotorlabs/rotorlabs.key \
  docs/sops/ssl/rotorlabs/rotorlabs.io.ca-bundle
```

The SSM parameters are overwritten only after validation succeeds. SSM retains parameter versions, which allows the previous values to be recovered if required.

### Roll back a rotation

List the available parameter versions:

```bash
aws ssm get-parameter-history \
  --name /nginx/tls/rotorlabs/certificate \
  --with-decryption \
  --query 'Parameters[].{version:Version,lastModified:LastModifiedDate}'

aws ssm get-parameter-history \
  --name /nginx/tls/rotorlabs/ca-bundle \
  --with-decryption \
  --query 'Parameters[].{version:Version,lastModified:LastModifiedDate}'

aws ssm get-parameter-history \
  --name /nginx/tls/rotorlabs/private-key \
  --with-decryption \
  --query 'Parameters[].{version:Version,lastModified:LastModifiedDate}'
```

Retrieve matching previous versions into protected local files:

```bash
umask 077
aws ssm get-parameter \
  --name '/nginx/tls/rotorlabs/certificate:VERSION' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > previous-certificate.pem

aws ssm get-parameter \
  --name '/nginx/tls/rotorlabs/ca-bundle:VERSION' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > previous-ca-bundle.pem

aws ssm get-parameter \
  --name '/nginx/tls/rotorlabs/private-key:VERSION' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > previous-private-key.pem
```

Deploy the matching files with the rotation script:

```bash
export NGINX_INSTANCE_ID="$(terraform output -raw nginx_instance_id)"
./scripts/rotate-nginx-tls.sh \
  previous-certificate.pem \
  previous-private-key.pem \
  previous-ca-bundle.pem
```

## Best Practices

- Never commit private keys, certificates, CSRs, or full chains.
- Keep private keys protected with permissions such as `chmod 600`.
- Use a separate customer-managed KMS key if the security requirements justify it.
- Keep the S3 Terraform state backend protected because it contains infrastructure metadata and secret references.
- Renew certificates before expiration rather than waiting for an outage.
- Test the new certificate locally before uploading it.
- Record the deployment date and certificate expiry in the operational calendar.
- Confirm DNS continues to point all three hostnames to the Nginx Elastic IP.
- Run `nginx -t` before every reload.
- Retain enough SSM parameter history to support rollback.
- Restrict operator permissions for SSM parameter access and SSM Run Command.
- Keep Namecheap account credentials protected and enable 2FA.

## Troubleshooting

### Certificate does not match the private key

The rotation script will stop before changing SSM. Compare the public-key hashes manually using the commands in the validation section. Confirm that the private key belongs to the CSR used to issue the certificate.

### Certificate does not cover a hostname

Inspect the SANs:

```bash
openssl x509 -text -noout -in rotorlabs.io.crt
```

The certificate must contain all three hostnames or a wildcard that covers them. A certificate for only one hostname cannot be used for the other two.

### Nginx reload fails

Connect to the Nginx instance and test the configuration:

```bash
sudo nginx -t
sudo journalctl -u nginx -n 100 --no-pager
```

Check that the certificate and key exist and have the expected permissions:

```bash
sudo ls -l /etc/nginx/ssl/rotorlabs.fullchain.pem /etc/nginx/ssl/rotorlabs.key
```

The rotation script installs the new files before running `nginx -t`. If validation fails, Nginx continues using the previously loaded certificate until a successful reload.

### SSM deployment command fails

Confirm:

- The local AWS identity can call `ssm:SendCommand` and `ssm:GetCommandInvocation`.
- `NGINX_INSTANCE_ID` identifies the current Nginx instance.
- The instance is managed and online in Systems Manager.
- The instance profile can read both TLS parameters and decrypt them with KMS.
- The AWS region is correct.

Retrieve the command output from the AWS Systems Manager console or rerun the script after correcting the issue.

### HTTPS connection fails

Check DNS, security groups, Nginx listeners, and the served certificate:

```bash
dig +short apps.rotorlabs.io
curl -vI https://apps.rotorlabs.io
sudo ss -lntp | grep ':443'
sudo nginx -t
```

The Nginx security group must allow inbound TCP `443`, and DNS must resolve each hostname to the Nginx Elastic IP.

## Resources

- [Namecheap SSL Documentation](https://www.namecheap.com/support/knowledgebase/subcategory/67/ssl-certificates/)
- [SSL Labs Server Test](https://www.ssllabs.com/ssltest/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [Let's Encrypt](https://letsencrypt.org/) - Free alternative for automated certificates

## Notes

- This repository uses purchased SSL certificates through Namecheap for production domains.
- For development or testing, consider Let's Encrypt with Certbot for automation.
- Namecheap typically uses Sectigo as the Certificate Authority.
