#!/bin/sh
set -e

# ACME certificate initialization script
# This script generates certificates on first startup
# 
# Configuration via environment variables:
# CERT_DOMAINS: List of certificates to generate (format: "name:domain1,domain2,... name2:domain3,...")
# Example: CERT_DOMAINS="example:*.example.net,example.net,webmail.example.net othersite:*.example.com,example.com"
#
# Or default configuration:

CERT_DIR="/acme-certs"

# Default configuration if CERT_DOMAINS is not set
if [ -z "${CERT_DOMAINS}" ]; then
    # Format: "cert_name:domain1,domain2,domain3 other_cert:domain4,domain5"
    # cert_name will be used as the folder name in /acme-certs/
    # Note: A wildcard (*.domain.com) already covers all subdomains
    CERT_DOMAINS="example.net:www.example.net,example.net"
fi

if [ -z "${ACME_SERVER}" ]; then
    # Default ACME server
    ACME_SERVER="zerossl"
fi

echo "=== Initialisation des certificats ACME ==="
echo "Date: $(date)"
echo "Configuration: ${CERT_DOMAINS}"
echo ""

# Configure Let's Encrypt server and register account
echo "--- Configuration ACME ---"
acme.sh --set-default-ca --server ${ACME_SERVER}
echo "✓ Serveur par défaut: ${ACME_SERVER}"

if [ -n "${ACME_EMAIL}" ]; then
    echo "Enregistrement du compte avec email: ${ACME_EMAIL}"
    acme.sh --register-account -m "${ACME_EMAIL}" --server ${ACME_SERVER} || echo "Compte déjà enregistré"
else
    echo "⚠ No email configured (ACME_EMAIL variable)"
fi

# Function to generate a certificate
# Parameters:
#   $1: certificate name (folder name)
#   $2: domains separated by commas (e.g.: "*.example.net,example.net,webmail.example.net")
generate_cert() {
    local cert_name="$1"
    local domains_csv="$2"
    local cert_file="${CERT_DIR}/${cert_name}/haproxy.pem"
    
    # Convert CSV domains to space-separated list
    local domains=$(echo "$domains_csv" | tr ',' ' ')
    
    # Extract the first domain from the list (for --install-cert)
    local first_domain=$(echo "$domains" | awk '{print $1}')
    
    echo ""
    echo "--- Traitement de ${cert_name} ---"
    echo "Domaines: ${domains}"
    
    # Check if the certificate already exists and is valid (>30 days)
    if [ -f "${cert_file}" ]; then
        echo "Certificat existant trouvé: ${cert_file}"
        # Check validity (optional)
        if openssl x509 -in "${cert_file}" -noout -checkend 2592000 2>/dev/null; then
            echo "✓ Certificate still valid for >30 days, skipping"
            return 0
        else
            echo "⚠ Certificate expiring soon, renewing..."
        fi
    else
        echo "No certificate found, generating..."
    fi
    
    # Create destination directory
    mkdir -p "${CERT_DIR}/${cert_name}"
    
    # Arguments for acme.sh (build the list of -d domain)
    local acme_args=""
    local domain_count=0
    for d in $domains; do
        acme_args="${acme_args} -d ${d}"
        domain_count=$((domain_count + 1))
    done
    
    echo "Number of domains/SNI: ${domain_count}"
    
    # Generate the certificate (Let's Encrypt is now the default server)
    echo "Commande: acme.sh --issue --dns dns_cf --dnssleep 30 ${acme_args} --keylength ec-384"
    
    if acme.sh --issue --dns dns_cf --dnssleep 30 ${acme_args} --keylength ec-384 2>&1 | tee /tmp/acme-${cert_name}.log; then
        echo "✓ Certificate successfully generated"
    else
        # If the certificate already exists in acme.sh, continue anyway
        if grep -q "Domains not changed" /tmp/acme-${cert_name}.log || grep -q "already issued" /tmp/acme-${cert_name}.log; then
            echo "ℹ Certificate already present in acme.sh, installing..."
        else
            echo "✗ Error generating certificate"
            cat /tmp/acme-${cert_name}.log
            return 1
        fi
    fi
    
    # Install the certificate (use the first domain in the list)
    echo "Installing certificate..."
    echo "Commande: acme.sh --install-cert -d '${first_domain}' --ecc"
    acme.sh --install-cert -d "${first_domain}" --ecc \
        --cert-file "${CERT_DIR}/${cert_name}/cert.pem" \
        --key-file "${CERT_DIR}/${cert_name}/key.pem" \
        --fullchain-file "${CERT_DIR}/${cert_name}/fullchain.pem"
    
    # Create the combined file for HAProxy
    cat "${CERT_DIR}/${cert_name}/fullchain.pem" "${CERT_DIR}/${cert_name}/cert.pem" "${CERT_DIR}/${cert_name}/key.pem" > "${cert_file}"
    chmod 644 "${cert_file}"
    
    echo "✓ Certificat installé: ${cert_file}"
    
    # Show SNI included in the certificate
    echo "SNI inclus dans le certificat:"
    openssl x509 -in "${cert_file}" -noout -text | grep -A 1 "Subject Alternative Name" || echo "  - $(openssl x509 -in "${cert_file}" -noout -subject | sed 's/.*CN=//')"
    
    # Check the certificate
    if openssl x509 -in "${cert_file}" -noout -dates; then
        echo "✓ Certificate valid"
    else
        echo "✗ Invalid certificate!"
        return 1
    fi
}

# Certificate generation
echo ""
echo "=== Certificate generation ==="

# Parse the CERT_DOMAINS variable and generate each certificate
# Format: "cert_name:domain1,domain2,domain3 other_cert:domain4,domain5"
for cert_config in ${CERT_DOMAINS}; do
    # Extract certificate name and domains
    cert_name=$(echo "$cert_config" | cut -d':' -f1)
    cert_domains=$(echo "$cert_config" | cut -d':' -f2)
    
    if [ -n "$cert_name" ] && [ -n "$cert_domains" ]; then
        generate_cert "$cert_name" "$cert_domains"
    else
        echo "⚠ Invalid configuration ignored: ${cert_config}"
    fi
done

echo ""
echo "=== Initialization completed successfully ==="
echo "Date: $(date)"
echo ""

# Create a flag file to indicate that init is done
touch /acme-certs/.init-done
echo "✓ Initialization flag created: /acme-certs/.init-done"

exit 0
