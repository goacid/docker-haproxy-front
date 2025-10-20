#!/bin/sh
set -e

# Script d'initialisation des certificats ACME
# Ce script génère les certificats au premier démarrage
# 
# Configuration via variables d'environnement :
# CERT_DOMAINS : Liste des certificats à générer (format : "nom:domaine1,domaine2,... nom2:domaine3,...")
# Exemple : CERT_DOMAINS="example:*.example.net,example.net,webmail.example.net othersite:*.example.com,example.com"
#
# Ou configuration par défaut :

CERT_DIR="/acme-certs"

# Configuration par défaut si CERT_DOMAINS n'est pas défini
if [ -z "${CERT_DOMAINS}" ]; then
    # Format : "nom_certificat:domaine1,domaine2,domaine3 autre_cert:domaine4,domaine5"
    # Le nom_certificat sera utilisé comme nom de dossier dans /acme-certs/
    # Note: Un wildcard (*.domain.com) couvre déjà tous les sous-domaines
    CERT_DOMAINS="example.net:www.example.net,example.net"
fi

if [ -z "${ACME_SERVER}" ]; then
    # Serveur ACME par défaut
    ACME_SERVER="zerossl"
fi

echo "=== Initialisation des certificats ACME ==="
echo "Date: $(date)"
echo "Configuration: ${CERT_DOMAINS}"
echo ""

# Configurer le serveur Let's Encrypt et enregistrer le compte
echo "--- Configuration ACME ---"
acme.sh --set-default-ca --server ${ACME_SERVER}
echo "✓ Serveur par défaut: ${ACME_SERVER}"

if [ -n "${ACME_EMAIL}" ]; then
    echo "Enregistrement du compte avec email: ${ACME_EMAIL}"
    acme.sh --register-account -m "${ACME_EMAIL}" --server ${ACME_SERVER} || echo "Compte déjà enregistré"
else
    echo "⚠ Aucun email configuré (variable ACME_EMAIL)"
fi

# Fonction pour générer un certificat
# Paramètres :
#   $1 : nom du certificat (nom du dossier)
#   $2 : domaines séparés par des virgules (ex: "*.example.net,example.net,webmail.example.net")
generate_cert() {
    local cert_name="$1"
    local domains_csv="$2"
    local cert_file="${CERT_DIR}/${cert_name}/haproxy.pem"
    
    # Convertir les domaines CSV en liste séparée par espaces
    local domains=$(echo "$domains_csv" | tr ',' ' ')
    
    # Extraire le premier domaine de la liste (pour --install-cert)
    local first_domain=$(echo "$domains" | awk '{print $1}')
    
    echo ""
    echo "--- Traitement de ${cert_name} ---"
    echo "Domaines: ${domains}"
    
    # Vérifier si le certificat existe déjà et est valide (>30 jours)
    if [ -f "${cert_file}" ]; then
        echo "Certificat existant trouvé: ${cert_file}"
        # Vérifier la validité (optionnel)
        if openssl x509 -in "${cert_file}" -noout -checkend 2592000 2>/dev/null; then
            echo "✓ Certificat encore valide pour >30 jours, skip"
            return 0
        else
            echo "⚠ Certificat expire bientôt, renouvellement..."
        fi
    else
        echo "Aucun certificat trouvé, génération..."
    fi
    
    # Créer le répertoire de destination
    mkdir -p "${CERT_DIR}/${cert_name}"
    
    # Arguments pour acme.sh (construire la liste de -d domaine)
    local acme_args=""
    local domain_count=0
    for d in $domains; do
        acme_args="${acme_args} -d ${d}"
        domain_count=$((domain_count + 1))
    done
    
    echo "Nombre de domaines/SNI: ${domain_count}"
    
    # Générer le certificat (Let's Encrypt est maintenant le serveur par défaut)
    echo "Commande: acme.sh --issue --dns dns_cf --dnssleep 30 ${acme_args} --keylength ec-384"
    
    if acme.sh --issue --dns dns_cf --dnssleep 30 ${acme_args} --keylength ec-384 2>&1 | tee /tmp/acme-${cert_name}.log; then
        echo "✓ Certificat généré avec succès"
    else
        # Si le certificat existe déjà dans acme.sh, continuer quand même
        if grep -q "Domains not changed" /tmp/acme-${cert_name}.log || grep -q "already issued" /tmp/acme-${cert_name}.log; then
            echo "ℹ Certificat déjà présent dans acme.sh, installation..."
        else
            echo "✗ Erreur lors de la génération du certificat"
            cat /tmp/acme-${cert_name}.log
            return 1
        fi
    fi
    
    # Installer le certificat (utiliser le premier domaine de la liste)
    echo "Installation du certificat..."
    echo "Commande: acme.sh --install-cert -d '${first_domain}' --ecc"
    acme.sh --install-cert -d "${first_domain}" --ecc \
        --cert-file "${CERT_DIR}/${cert_name}/cert.pem" \
        --key-file "${CERT_DIR}/${cert_name}/key.pem" \
        --fullchain-file "${CERT_DIR}/${cert_name}/fullchain.pem"
    
    # Créer le fichier combiné pour HAProxy
    cat "${CERT_DIR}/${cert_name}/fullchain.pem" "${CERT_DIR}/${cert_name}/cert.pem" "${CERT_DIR}/${cert_name}/key.pem" > "${cert_file}"
    chmod 644 "${cert_file}"
    
    echo "✓ Certificat installé: ${cert_file}"
    
    # Afficher les SNI inclus dans le certificat
    echo "SNI inclus dans le certificat:"
    openssl x509 -in "${cert_file}" -noout -text | grep -A 1 "Subject Alternative Name" || echo "  - $(openssl x509 -in "${cert_file}" -noout -subject | sed 's/.*CN=//')"
    
    # Vérifier le certificat
    if openssl x509 -in "${cert_file}" -noout -dates; then
        echo "✓ Certificat valide"
    else
        echo "✗ Certificat invalide!"
        return 1
    fi
}

# Génération des certificats
echo ""
echo "=== Génération des certificats ==="

# Parser la variable CERT_DOMAINS et générer chaque certificat
# Format: "cert_name:domain1,domain2,domain3 other_cert:domain4,domain5"
for cert_config in ${CERT_DOMAINS}; do
    # Extraire le nom du certificat et les domaines
    cert_name=$(echo "$cert_config" | cut -d':' -f1)
    cert_domains=$(echo "$cert_config" | cut -d':' -f2)
    
    if [ -n "$cert_name" ] && [ -n "$cert_domains" ]; then
        generate_cert "$cert_name" "$cert_domains"
    else
        echo "⚠ Configuration invalide ignorée: ${cert_config}"
    fi
done

echo ""
echo "=== Initialisation terminée avec succès ==="
echo "Date: $(date)"
echo ""

# Créer un fichier de flag pour indiquer que l'init est terminée
touch /acme-certs/.init-done
echo "✓ Flag d'initialisation créé: /acme-certs/.init-done"

exit 0
