#!/bin/sh
set -e

# ACME certificate renewal script
# Called daily by Ofelia
# Uses the CERT_DOMAINS variable to determine which certificates to renew

CERT_DIR="/acme-certs"

# Default configuration if CERT_DOMAINS is not set
if [ -z "${CERT_DOMAINS}" ]; then
    CERT_DOMAINS="example.net:*.example.net,example.net"
fi

echo "=== ACME certificate renewal ==="
echo "Date: $(date)"
echo "Configuration: ${CERT_DOMAINS}"
echo ""

# Function to renew a certificate
# Parameters:
#   $1: certificate name (folder name)
#   $2: domains separated by commas
renew_cert() {
    cert_name="$1"
    domains_csv="$2"
    cert_file="${CERT_DIR}/${cert_name}/haproxy.pem"
    
    # Convert CSV domains to space-separated list
    domains=$(echo "$domains_csv" | tr ',' ' ')
    
    # Extract the first domain
    first_domain=$(echo "$domains" | awk '{print $1}')
    
    echo ""
    echo "--- Renewing ${cert_name} ---"
    echo "Domaines: ${domains}"
    
    # Check if the certificate exists
    if [ ! -f "${cert_file}" ]; then
        echo "⚠ Certificate not found, initial generation..."
        # Call the init script for this certificate
        sh /scripts/init-certs.sh
        return $?
    fi
    
    # Check if the certificate expires soon (< 30 days)
    if openssl x509 -in "${cert_file}" -noout -checkend 2592000 2>/dev/null; then
        echo "✓ Certificate still valid for >30 days, skipping"
        openssl x509 -in "${cert_file}" -noout -dates | grep "notAfter"
        return 0
    fi
    
    echo "⚠ Certificate expiring soon, renewing..."
    
    # Build acme.sh arguments
    acme_args=""
    for d in $domains; do
        acme_args="${acme_args} -d ${d}"
    done
    
    # Renew the certificate (force renewal)
    echo "Commande: acme.sh --renew ${acme_args} --ecc --force"
    
    if acme.sh --renew ${acme_args} --ecc --force 2>&1 | tee /tmp/renew-${cert_name}.log; then
        echo "✓ Certificate renewed"
    else
        if grep -q "Domains not changed" /tmp/renew-${cert_name}.log; then
            echo "ℹ Domains unchanged, reinstalling..."
        else
            echo "✗ Error during renewal"
            cat /tmp/renew-${cert_name}.log
            return 1
        fi
    fi
    
    # Reinstall the certificate
    echo "Reinstalling certificate..."
    acme.sh --install-cert -d "${first_domain}" --ecc \
        --cert-file "${CERT_DIR}/${cert_name}/cert.pem" \
        --key-file "${CERT_DIR}/${cert_name}/key.pem" \
        --fullchain-file "${CERT_DIR}/${cert_name}/fullchain.pem"
    
    # Recreate the combined file for HAProxy
    cat "${CERT_DIR}/${cert_name}/fullchain.pem" "${CERT_DIR}/${cert_name}/cert.pem" "${CERT_DIR}/${cert_name}/key.pem" > "${cert_file}"
    chmod 644 "${cert_file}"
    
    echo "✓ Certificate reinstalled: ${cert_file}"
    
    # Display the new expiration date
    openssl x509 -in "${cert_file}" -noout -dates | grep "notAfter"
}

# Parse CERT_DOMAINS and renew each certificate
renewed_count=0
for cert_config in ${CERT_DOMAINS}; do
    cert_name=$(echo "$cert_config" | cut -d':' -f1)
    cert_domains=$(echo "$cert_config" | cut -d':' -f2)
    
    if [ -n "$cert_name" ] && [ -n "$cert_domains" ]; then
        if renew_cert "$cert_name" "$cert_domains"; then
            renewed_count=$((renewed_count + 1))
        fi
    fi
done

# Create a renewal flag if at least one certificate was renewed
if [ $renewed_count -gt 0 ]; then
    echo ""
    echo "=== Certificates renewed ==="
    echo "Creating renewal flag..."
    touch /tmp/certs-renewed.flag
    echo "✓ Flag created: /tmp/certs-renewed.flag"
    echo "ℹ Services will be reloaded by the Ofelia job 'reload_services'"
fi

echo ""
echo ""
echo "=== Renewal completed ==="
echo "Date: $(date)"
echo "Certificates processed: ${renewed_count}"
echo ""

exit 0

exit 0
