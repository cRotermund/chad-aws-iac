# SSL Certificate Management for rotorlabs

This directory contains scripts and templates for generating SSL certificates for rotorlabs domains through Namecheap.

## Overview

This is a Standard Operating Procedure (SOP) for:
- Generating private keys and Certificate Signing Requests (CSRs)
- Submitting CSRs to Namecheap for SSL certificate issuance
- Managing certificate files securely

**IMPORTANT:** Never commit actual certificates, private keys, or CSRs to this repository. Only config and scripts are version controlled.

## Files

- `README.md` - This documentation
- `rotorlabs.cnf` - OpenSSL configuration for rotorlabs CSR generation
- `generate-csr.sh` - Script to generate private key and CSR
- `.gitignore` - Ensures secrets are not committed

## Quick Start

### 1. Generate Private Key and CSR

```bash
cd docs/ssl/rotorlabs
./generate-csr.sh
```

This creates:
- `rotorlabs.key` - Private key (keep this secret!)
- `rotorlabs.csr` - Certificate Signing Request (submit to Namecheap)
- `rotorlabs.cnf` - OpenSSL config used for generation

### 2. Submit CSR to Namecheap

1. Log into Namecheap account
2. Navigate to SSL Certificates → Manage
3. Click "Activate" on purchased certificate
4. Paste the contents of `rotorlabs.csr` into the CSR field
5. Select server type: **nginx** (or appropriate)
6. Complete domain validation (email, DNS, or HTTP file)

### 3. Download Certificate from Namecheap

Once validated, Namecheap provides:
- `rotorlabs.io.crt` - Your domain certificate
- `rotorlabs.io.ca-bundle` - Intermediate certificates

## Renewal Process

SSL certificates typically last 1 year. Set a reminder to renew 30 days before expiration.

1. Generate new CSR using same script (can reuse private key or generate new one)
2. Renew certificate through Namecheap
3. Submit CSR and complete validation
4. Download and deploy new certificate

## Security Best Practices

- **Never commit private keys** - Use .gitignore to prevent accidents
- **Protect private keys** - Set proper permissions (`chmod 600 *.key`)
- **Use strong keys** - 2048-bit RSA minimum (4096-bit recommended)
- **Store backups securely** - Keep encrypted backups of keys in secure location
- **Rotate certificates** - Don't wait until expiration to renew
- **Monitor expiration** - Set up alerts for certificate expiration

## Troubleshooting

### CSR doesn't match private key
```bash
# Verify key and CSR match
openssl rsa -noout -modulus -in rotorlabs.key | openssl md5
openssl req -noout -modulus -in rotorlabs.csr | openssl md5
# Hashes should match
```

### View CSR details
```bash
openssl req -text -noout -verify -in rotorlabs.csr
```

### View certificate details
```bash
openssl x509 -text -noout -in apps.rotorlabs.io.crt
openssl x509 -text -noout -in admin.rotorlabs.io.crt
openssl x509 -text -noout -in apis.rotorlabs.io.crt
```

### Test SSL configuration
```bash
# Check certificate expiration
openssl s_client -connect apps.rotorlabs.io:443 -servername apps.rotorlabs.io < /dev/null | openssl x509 -noout -dates
openssl s_client -connect admin.rotorlabs.io:443 -servername admin.rotorlabs.io < /dev/null | openssl x509 -noout -dates
openssl s_client -connect apis.rotorlabs.io:443 -servername apis.rotorlabs.io < /dev/null | openssl x509 -noout -dates

# Test SSL connection
curl -vI https://apps.rotorlabs.io
curl -vI https://admin.rotorlabs.io
curl -vI https://apis.rotorlabs.io
```

Note: Wildcard certificates typically require DNS validation.

## Multi-Domain (SAN) Certificates

For multiple domains in one certificate:

```ini
[alt_names]
DNS.1 = yourdomain.com
DNS.2 = www.yourdomain.com
DNS.3 = api.yourdomain.com
DNS.4 = anotherdomain.com
```

## Resources

- [Namecheap SSL Documentation](https://www.namecheap.com/support/knowledgebase/subcategory/67/ssl-certificates/)
- [SSL Labs Server Test](https://www.ssllabs.com/ssltest/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [Let's Encrypt](https://letsencrypt.org/) - Free alternative for automated certificates

## Notes

- This repo uses purchased SSL certificates through Namecheap for production domains
- For development/testing, consider Let's Encrypt with certbot for automation
- Namecheap typically uses Sectigo (formerly Comodo) as the Certificate Authority
- Keep your Namecheap account credentials secure and enable 2FA
