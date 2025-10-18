FROM haproxy:latest

# Passer en root pour installer les paquets
USER root

RUN apt-get update && \
    apt-get install -y \
        vim \
        unzip \
        procps \
        htop \
        telnet \
        curl \
        wget \
        net-tools \
        iputils-ping \
        dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Revenir à l'utilisateur haproxy par défaut
USER haproxy