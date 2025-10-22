#!/bin/sh
set -e

# Service reload script after certificate renewal
# This script must be run by a container with access to Docker
# (typically launched by Ofelia which has the Docker socket mounted)

echo "=== Services reload ==="
echo "Date: $(date)"

# Reload HAProxy front
echo ""
echo "--- haproxy-front ---"
if docker kill -s USR2 haproxy-front 2>/dev/null; then
    echo "✓ haproxy-front reloaded (USR2 signal sent)"
else
    echo "⚠ Unable to reload haproxy-front (container not found or error)"
fi

# Reload HAProxy mailcow
echo ""
echo "--- haproxy-mailcow ---"
if docker kill -s USR2 haproxy-mailcow 2>/dev/null; then
    echo "✓ haproxy-mailcow reloaded (USR2 signal sent)"
else
    echo "⚠ Unable to reload haproxy-mailcow (container not found or error)"
fi

# Reload Postfix
echo ""
echo "--- postfix-mailcow ---"
if docker exec mailcowdockerized-postfix-mailcow-1 postfix reload 2>/dev/null; then
    echo "✓ postfix-mailcow reloaded"
else
    echo "⚠ Unable to reload postfix-mailcow (container not found or error)"
fi

# Reload Dovecot
echo ""
echo "--- dovecot-mailcow ---"
if docker exec mailcowdockerized-dovecot-mailcow-1 doveadm reload 2>/dev/null; then
    echo "✓ dovecot-mailcow reloaded"
else
    echo "⚠ Unable to reload dovecot-mailcow (container not found or error)"
fi

echo ""
echo "=== Reload completed ==="
echo "Date: $(date)"
echo ""

exit 0
