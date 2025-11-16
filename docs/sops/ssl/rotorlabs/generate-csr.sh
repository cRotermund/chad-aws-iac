#!/bin/bash
#
# SSL CSR and Private Key Generator for Namecheap
#
# Usage: ./generate-csr.sh domain.com [--wildcard]
#
# This script generates:
#   - Private key (domain.com.key)
#   - Certificate Signing Request (domain.com.csr)
#   - OpenSSL config file (domain.com.cnf)
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DOMAIN="rotorlabs"
WILDCARD=false

# Check for wildcard flag
if [ $# -gt 1 ] && [ "$2" == "--wildcard" ]; then
    WILDCARD=true
fi

# Output filenames
KEY_FILE="${DOMAIN}.key"
CSR_FILE="${DOMAIN}.csr"
CNF_FILE="${DOMAIN}.cnf"

echo -e "${GREEN}Generating SSL certificate files for: ${DOMAIN}${NC}"
if [ "$WILDCARD" = true ]; then
    echo -e "${YELLOW}Wildcard certificate requested (*.${DOMAIN})${NC}"
fi
echo ""

# Check if files already exist
if [ -f "$KEY_FILE" ] || [ -f "$CSR_FILE" ]; then
    echo -e "${YELLOW}Warning: One or more files already exist:${NC}"
    [ -f "$KEY_FILE" ] && echo "  - $KEY_FILE"
    [ -f "$CSR_FILE" ] && echo "  - $CSR_FILE"
    echo ""
    read -p "Overwrite existing files? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborted${NC}"
        exit 1
    fi
fi

if [ -f "$CNF_FILE" ]; then
    echo -e "${GREEN}✓ Configuration located: ${CNF_FILE}${NC}"
else 
    echo -e "${RED}✗ Error: Configuration file not found: ${CNF_FILE}${NC}"
    exit 1
fi

# Generate private key
echo -e "${GREEN}Generating 2048-bit RSA private key...${NC}"
openssl genrsa -out "$KEY_FILE" 2048 2>/dev/null

# Set proper permissions on private key
chmod 600 "$KEY_FILE"

echo -e "${GREEN}✓ Private key generated: ${KEY_FILE}${NC}"
echo ""

# Generate CSR
echo -e "${GREEN}Generating Certificate Signing Request (CSR)...${NC}"
openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" -config "$CNF_FILE"

echo -e "${GREEN}✓ CSR generated: ${CSR_FILE}${NC}"
echo ""

# Display CSR details
echo -e "${GREEN}CSR Details:${NC}"
echo "────────────────────────────────────────────────"
openssl req -text -noout -in "$CSR_FILE" | grep -A 1 "Subject:"
echo ""
openssl req -text -noout -in "$CSR_FILE" | grep -A 10 "Subject Alternative Name"
echo "────────────────────────────────────────────────"
echo ""

# Display CSR content for copy/paste
echo -e "${GREEN}CSR Content (submit this to Namecheap):${NC}"
echo "────────────────────────────────────────────────"
cat "$CSR_FILE"
echo "────────────────────────────────────────────────"
echo ""

# Summary
echo -e "${GREEN}✓ Complete! Files generated:${NC}"
echo "  • ${KEY_FILE} - Private key (keep this secret!)"
echo "  • ${CSR_FILE} - Certificate Signing Request (submit to Namecheap)"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Copy the CSR content above"
echo "  2. Log into Namecheap → SSL Certificates → Activate"
echo "  3. Paste the CSR"
echo "  4. Select server type: nginx"
echo "  5. Complete domain validation"
echo "  6. Download certificate files"
echo "  7. See README.md for deployment instructions"
echo ""

echo -e "${RED}IMPORTANT:${NC}"
echo "  • Never commit ${KEY_FILE} to version control"
echo "  • Store ${KEY_FILE} securely - you'll need it to use the certificate"
echo "  • Create encrypted backups of ${KEY_FILE}"
echo ""

# Verify key and CSR match
echo -e "${GREEN}Verifying key and CSR match...${NC}"
KEY_MODULUS=$(openssl rsa -noout -modulus -in "$KEY_FILE" 2>/dev/null | openssl md5)
CSR_MODULUS=$(openssl req -noout -modulus -in "$CSR_FILE" 2>/dev/null | openssl md5)

if [ "$KEY_MODULUS" == "$CSR_MODULUS" ]; then
    echo -e "${GREEN}✓ Verification successful - key and CSR match${NC}"
else
    echo -e "${RED}✗ Error: Key and CSR do not match!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Done!${NC}"
