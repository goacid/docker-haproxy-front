#!/bin/sh
set -e

# Script de renouvellement des certificats ACME
# Appelé quotidiennement par Ofelia
# Utilise la variable CERT_DOMAINS pour déterminer quels certificats renouveler

CERT_DIR="/acme-certs"

# Configuration par défaut si CERT_DOMAINS n'est pas défini
if [ -z "${CERT_DOMAINS}" ]; then
    CERT_DOMAINS="example.net:*.example.net,example.net"
fi

echo "=== Renouvellement des certificats ACME ==="
echo "Date: $(date)"
echo "Configuration: ${CERT_DOMAINS}"
echo ""

# Fonction pour renouveler un certificat
# Paramètres :
#   $1 : nom du certificat (nom du dossier)
#   $2 : domaines séparés par des virgules
renew_cert() {
    cert_name="$1"
    domains_csv="$2"
    cert_file="${CERT_DIR}/${cert_name}/haproxy.pem"
    
    # Convertir les domaines CSV en liste séparée par espaces
    domains=$(echo "$domains_csv" | tr ',' ' ')
    
    # Extraire le premier domaine
    first_domain=$(echo "$domains" | awk '{print $1}')
    
    echo ""
    echo "--- Renouvellement de ${cert_name} ---"
    echo "Domaines: ${domains}"
    
    # Vérifier si le certificat existe
    if [ ! -f "${cert_file}" ]; then
        echo "⚠ Certificat non trouvé, génération initiale..."
        # Appeler le script d'init pour ce certificat
        sh /scripts/init-certs.sh
        return $?
    fi
    
    # Vérifier si le certificat expire bientôt (< 30 jours)
    if openssl x509 -in "${cert_file}" -noout -checkend 2592000 2>/dev/null; then
        echo "✓ Certificat encore valide pour >30 jours, skip"
        openssl x509 -in "${cert_file}" -noout -dates | grep "notAfter"
        return 0
    fi
    
    echo "⚠ Certificat expire bientôt, renouvellement..."
    
    # Construire les arguments acme.sh
    acme_args=""
    for d in $domains; do
        acme_args="${acme_args} -d ${d}"
    done
    
    # Renouveler le certificat (force le renouvellement)
    echo "Commande: acme.sh --renew ${acme_args} --ecc --force"
    
    if acme.sh --renew ${acme_args} --ecc --force 2>&1 | tee /tmp/renew-${cert_name}.log; then
        echo "✓ Certificat renouvelé"
    else
        if grep -q "Domains not changed" /tmp/renew-${cert_name}.log; then
            echo "ℹ Domaines inchangés, réinstallation..."
        else
            echo "✗ Erreur lors du renouvellement"
            cat /tmp/renew-${cert_name}.log
            return 1
        fi
    fi
    
    # Réinstaller le certificat
    echo "Réinstallation du certificat..."
    acme.sh --install-cert -d "${first_domain}" --ecc \
        --cert-file "${CERT_DIR}/${cert_name}/cert.pem" \
        --key-file "${CERT_DIR}/${cert_name}/key.pem" \
        --fullchain-file "${CERT_DIR}/${cert_name}/fullchain.pem"
    
    # Recréer le fichier combiné pour HAProxy
    cat "${CERT_DIR}/${cert_name}/fullchain.pem" "${CERT_DIR}/${cert_name}/key.pem" > "${cert_file}"
    chmod 644 "${cert_file}"
    
    echo "✓ Certificat réinstallé: ${cert_file}"
    
    # Afficher la nouvelle date d'expiration
    openssl x509 -in "${cert_file}" -noout -dates | grep "notAfter"
}

# Parser CERT_DOMAINS et renouveler chaque certificat
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

# Créer un flag de renouvellement si au moins un certificat a été renouvelé
if [ $renewed_count -gt 0 ]; then
    echo ""
    echo "=== Certificats renouvelés ==="
    echo "Création du flag de renouvellement..."
    touch /tmp/certs-renewed.flag
    echo "✓ Flag créé : /tmp/certs-renewed.flag"
    echo "ℹ Les services seront rechargés par le job Ofelia 'reload_services'"
fi

echo ""
echo "=== Renouvellement terminé ==="
echo "Date: $(date)"
echo "Certificats traités: ${renewed_count}"
echo ""

exit 0
