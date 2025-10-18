#!/bin/sh
set -e

# Script de rechargement des services après renouvellement de certificats
# Ce script doit être exécuté par un container ayant accès à Docker
# (typiquement lancé par Ofelia qui a le socket Docker monté)

echo "=== Rechargement des services ==="
echo "Date: $(date)"

# Recharger HAProxy front
echo ""
echo "--- haproxy-front ---"
if docker kill -s USR2 haproxy-front 2>/dev/null; then
    echo "✓ haproxy-front rechargé (signal USR2 envoyé)"
else
    echo "⚠ Impossible de recharger haproxy-front (container non trouvé ou erreur)"
fi

# Recharger HAProxy mailcow
echo ""
echo "--- haproxy-mailcow ---"
if docker kill -s USR2 haproxy-mailcow 2>/dev/null; then
    echo "✓ haproxy-mailcow rechargé (signal USR2 envoyé)"
else
    echo "⚠ Impossible de recharger haproxy-mailcow (container non trouvé ou erreur)"
fi

# Recharger Postfix
echo ""
echo "--- postfix-mailcow ---"
if docker exec mailcowdockerized-postfix-mailcow-1 postfix reload 2>/dev/null; then
    echo "✓ postfix-mailcow rechargé"
else
    echo "⚠ Impossible de recharger postfix-mailcow (container non trouvé ou erreur)"
fi

# Recharger Dovecot
echo ""
echo "--- dovecot-mailcow ---"
if docker exec mailcowdockerized-dovecot-mailcow-1 doveadm reload 2>/dev/null; then
    echo "✓ dovecot-mailcow rechargé"
else
    echo "⚠ Impossible de recharger dovecot-mailcow (container non trouvé ou erreur)"
fi

echo ""
echo "=== Rechargement terminé ==="
echo "Date: $(date)"
echo ""

exit 0
