#!/bin/bash

set -e

# Function to prompt user for confirmation
yes_or_no() {
    while true; do
        read -p "$1 [Y/n]: " yn
        yn=${yn:-Y}
        case $yn in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no.";;
        esac
    done
}

# Create directories if they do not exist
dirs=("data/certs" "data/conf" "data/scripts" "volumes/acme")
for dir in "${dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        if yes_or_no "Create directory $dir?"; then
            mkdir -p "$dir"
            echo "Created $dir."
        else
            echo "Skipped $dir."
        fi
    else
        echo "$dir already exists."
    fi
done

# Copy .env.template to .env if .env does not exist
if [ ! -f ".env" ]; then
    if yes_or_no "Copy .env.template to .env?"; then
        cp .env.template .env
        echo ".env created from template."
    else
        echo "Skipped .env creation."
    fi
else
    echo ".env already exists."
fi

# Copy scripts from bootstrap_scripts to data/scripts
if yes_or_no "Do you want to copy scripts from bootstrap_scripts to data/scripts?"; then
    cp -a bootstrap_scripts/. data/scripts/
    echo "Scripts copied to data/scripts."
    echo "These files were copied from ./bootstrap_scripts" > data/scripts/readme.txt
else
    echo "Skipped copying scripts."
fi

# Copy configuration files from bootstrap_conf to data/conf
if yes_or_no "Do you want to copy configuration files from bootstrap_conf to data/conf?"; then
    cp -a bootstrap_conf/. data/conf/
    echo "Configuration files copied to data/conf."
    echo "These files were copied from ./bootstrap_conf" > data/conf/readme.txt
else
    echo "Skipped copying configuration files."
fi

echo "Setup completed."