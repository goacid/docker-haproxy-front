# HAProxy + ACME (Let's Encrypt) for Mailcow

This project provides an advanced HAProxy configuration to serve as a secure reverse proxy for Mailcow, with automatic SSL/TLS certificate management via ACME (Let's Encrypt) and Cloudflare DNS validation.

This project only exposes the Mailcow web interface and forwards to a Mailcow HAProxy that exposes all other services.

Why only expose the web interface? If you want to self-host other web services, you can add ACLs in this HAProxy to forward to your other services. This allows Mailcow to operate independently and see this HAProxy as the web front for all services.

See the mailcow-haproxy project.

## How it works

- **HAProxy** terminates SSL/TLS at the front and relays traffic to Mailcow internally.
- **Certificates** are generated and renewed automatically via acme.sh (Let's Encrypt) with Cloudflare DNS challenge.
- **Multi-SNI**: supports multiple certificates for different domains.
- **Automatic renewal** orchestrated by Ofelia (docker cron).
- **Automatic reload** of HAProxy and mail services after each renewal.

## Quick Start

1. Copy the configuration template:
   ```bash
   cp .env.template .env
   nano .env
   ```
2. Fill in your variables:
   - `CERT_DOMAINS`: domains to certify (see examples below)
   - `CF_TOKEN`: Cloudflare API token (Zone:DNS:Edit)
   - `ACME_EMAIL`: email for Let's Encrypt
3. Run the setup script to prepare the environment:
   ```bash
   ./setup.sh
   ```
4. Start the services:
   ```bash
   docker compose -f docker-compose.yml up -d
   ```
5. Check the logs:
   ```bash
   docker logs -f acme-front
   docker logs -f haproxy-front
   docker logs -f ofelia-front
   ```

### What does setup.sh do?

- Interactively creates required directories (`data/certs`, `data/conf`, `data/scripts`, `volumes/acme`).
- Copies `env.template` to `.env` if not present.
- Copies all scripts from `bootstrap_scripts` to `data/scripts` and creates a `readme.txt` indicating the source.
- Copies all configuration files from `bootstrap_conf` to `data/conf` and creates a `readme.txt` indicating the source.

## CERT_DOMAINS Examples

- Wildcard + root domain (recommended):
  ```bash
  CERT_DOMAINS="toto.com:*.toto.com,toto.com"
  ```
- Specific domains:
  ```bash
  CERT_DOMAINS="toto.com:www.toto.com,mail.toto.com,toto.com"
  ```
- Multiple certificates:
  ```bash
  CERT_DOMAINS="site1:*.site1.com,site1.com site2:*.site2.com,site2.com"
  ```

**Warning:** Do not mix wildcard and explicit subdomains in the same certificate (Let's Encrypt will refuse).

## File Structure
After setup.sh has been launched

```
example.net/haproxy/
├── .env                # Main configuration
├── env.template       # Configuration example
├── docker-compose.yml
├── haproxy.dockerfile  # Custom Dockerfile (diagnostic tools installed)
├── data/               # For containers data
│   ├── certs/          # Generated certificates
│   ├── conf/
│   │   └── haproxy.cfg # HAProxy configuration
│   └── scripts/
│       ├── init-certs.sh      # Initial certificate generation
│       ├── renew-certs.sh     # Automatic renewal
│       └── reload-services.sh # Service reload
└── volumes/            # Containers volumes are here
    ├── acme/           # ACME data
    └── ...
```

## Maintenance & Troubleshooting

- Check certificates:
  ```bash
  ls -la data/certs/
  openssl x509 -in data/certs/toto.com/haproxy.pem -noout -dates
  ```
- Force renewal:
  ```bash
  docker exec acme-front sh /scripts/renew-certs.sh
  docker exec cert-reloader-front sh /scripts/reload-services.sh
  ```
- Check Ofelia jobs:
  ```bash
  docker logs ofelia-front 2>&1 | grep "New job registered"
  ```
- Protect secrets:
  ```bash
  chmod 600 .env
  ```


## docker-compose.yml detailed explanation

The `docker-compose.yml` file orchestrates all the containers and networking required for secure, automated SSL/TLS termination and certificate management in front of Mailcow. Here is a detailed breakdown of its main components:

### Services

- **acme-haproxy**: Runs the `acme.sh` client to automatically issue and renew SSL/TLS certificates from Let's Encrypt using the DNS-01 challenge (Cloudflare). It mounts volumes for persistent certificate storage and scripts, and uses environment variables for configuration. It includes a healthcheck to ensure certificates are initialized before dependent services start. Ofelia jobs are used to schedule automatic certificate renewal.

- **front-haproxy**: Runs the HAProxy reverse proxy, which terminates HTTPS connections and forwards traffic to Mailcow or other internal services. It depends on `acme-haproxy` to ensure certificates are available before starting. It mounts configuration and certificate volumes, exposes ports 80 and 443, and connects to both the external Mailcow network and an internal front network. Logging is configured for rotation.

- **cert-reloader**: A lightweight service that reloads HAProxy and other services after certificates are renewed. It is triggered by Ofelia jobs and has access to Docker and scripts via mounted volumes.

- **ofelia-haproxy**: Runs the Ofelia job scheduler, which executes jobs based on Docker labels. It manages scheduled tasks such as certificate renewal and service reloads, and depends on the other services to ensure proper startup order.

### Networks

- **mailcow-network**: An external Docker network that connects this proxy setup to the Mailcow stack. It must already exist and is referenced by name.
- **haproxy-front**: An internal bridge network for the proxy and related services, with custom IPv4/IPv6 subnets and bridge name. This network isolates the front-end proxy from the rest of the system while allowing controlled access.

### Volumes

- **acme-data**: A persistent volume for ACME client data, mapped to a configurable path on the host. This ensures certificates and account data survive container restarts and upgrades.

### Key Features

- Automated SSL/TLS certificate management and renewal with Let's Encrypt and Cloudflare DNS.
- Secure, isolated reverse proxy with HAProxy, supporting multiple domains and SNI.
- Scheduled, automated reloads of proxy and mail services after certificate changes.
- Modular, maintainable Docker Compose structure for easy extension and troubleshooting.

This setup ensures that Mailcow and any other internal services can be securely exposed to the internet with minimal manual intervention, leveraging best practices for automation and security.


## Useful Resources

- [HAProxy](https://www.haproxy.org/#docs)
- [ACME.sh](https://github.com/acmesh-official/acme.sh)
- [Let's Encrypt](https://letsencrypt.org/docs/)
- [Cloudflare API](https://developers.cloudflare.com/api/)
- [Ofelia](https://github.com/mcuadros/ofelia)

---
