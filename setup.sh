#!/usr/bin/env bash
set -euxo pipefail

# Unset any custom DOCKER_HOST so Docker uses the default socket.
unset DOCKER_HOST

# Request sudo permission upfront.
sudo -v

########################################
# ANSI Colors
########################################
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

########################################
# Spinner for Long Commands
########################################
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr="|/-\\"
    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#spinstr}; i++ )); do
            printf " [%c]  " "${spinstr:$i:1}"
            sleep $delay
            printf "\b\b\b\b\b\b"
        done
    done
    printf "    \b\b\b\b"
}

run_with_spinner() {
    "$@" > /dev/null 2>&1 &
    local pid=$!
    spinner $pid
    wait $pid
}

########################################
# Capture Output with tee
########################################
exec > >(tee /tmp/immich_setup_summary.txt) 2>&1
clear

echo "${GREEN}Starting Immich Setup Script on Fedora...${RESET}"
echo

########################################
# OS Detection (Fedora Only)
########################################
if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    echo "${RED}OS detection failed. Exiting.${RESET}"
    exit 1
fi

if [ "$ID" != "fedora" ]; then
    echo "${RED}This script is designed for Fedora only. Detected distro: $ID. Exiting.${RESET}"
    exit 1
fi

echo "${GREEN}Distro detected: Fedora ($VERSION_ID)${RESET}"
echo

########################################
# Docker Installation
########################################
if ! command -v docker &>/dev/null; then
    echo "${YELLOW}Docker not found. Installing Docker for Fedora...${RESET}"
    sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest* docker-logrotate docker-engine || true
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl start docker
    sudo systemctl enable docker
else
    echo "${GREEN}Docker is already installed.${RESET}"
fi
echo

########################################
# Docker Version & Daemon Status (using sudo)
########################################
echo "${GREEN}Docker Version & Daemon Status:${RESET}"
sudo docker version
sudo systemctl is-active docker
echo

########################################
# Docker Group Check and Auto‑Logout
########################################
if ! getent group docker >/dev/null; then
    echo "${YELLOW}Group 'docker' does not exist. Creating group 'docker'...${RESET}"
    sudo groupadd docker
fi

if ! groups "$USER" | grep -qw docker; then
    echo "${YELLOW}You are not in the 'docker' group. Adding $USER to the 'docker' group...${RESET}"
    sudo usermod -aG docker "$USER"
    echo "${GREEN}Done. Press Enter to log out now. (You will need to log back in and re-run this script.)${RESET}"
    read -r
    sudo pkill -KILL -u "$USER"
    exit 0
fi
echo

########################################
# Restore Backup if Needed
########################################
if [ ! -d "./immich/library" ]; then
    found_backup=false
    for b in backup_[0-9][0-9][0-9][0-9][0-9][0-9]; do
        if [ -d "$b" ]; then
            echo "${YELLOW}Found backup directory: $b. Restoring it to ./immich/library...${RESET}"
            sudo mv "$b" "./immich/library"
            found_backup=true
            break
        fi
    done
    if [ "$found_backup" = false ]; then
        echo "${YELLOW}No backup directory found to restore.${RESET}"
    fi
fi
echo

########################################
# Immich Setup (Timeout 30s)
########################################
if ! sudo docker ps -a --filter=name=immich_server | grep -q immich_server; then
    echo "${YELLOW}Immich not found. Setting it up using official docker-compose instructions...${RESET}"
    mkdir -p ~/immich && cd ~/immich || exit 1
    run_with_spinner wget -q -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
    run_with_spinner wget -q -O .env https://github.com/immich-app/immich/releases/latest/download/example.env
    echo "${YELLOW}Starting Immich (timeout 30s)...${RESET}"
    run_with_spinner timeout 30 sudo docker compose up -d || { echo "${RED}docker compose up timed out. Exiting.${RESET}"; exit 1; }
    echo "${GREEN}Immich setup complete.${RESET}"
else
    echo "${GREEN}Immich container already exists; skipping setup.${RESET}"
fi
echo

########################################
# Protecting Immich Data (Backup)
########################################
backup_required=false
data_dir="./immich/library"
if [ -d "$data_dir" ]; then
    echo "${YELLOW}Stopping Immich container to backup data directory...${RESET}"
    sudo docker stop immich_server || true
    random_dir=$(printf "%06d" $((RANDOM % 1000000)))
    backup_dir="./backup_${random_dir}"
    echo "${YELLOW}Moving $data_dir to $backup_dir for backup...${RESET}"
    sudo rm -rf "$backup_dir"
    sudo mv "$data_dir" "$backup_dir
::contentReference[oaicite:1]{index=1}
 
