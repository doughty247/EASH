#!/usr/bin/env bash
set -euo pipefail

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
    run_with_spinner sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest* docker-logrotate docker-engine || true
    run_with_spinner sudo dnf -y install dnf-plugins-core
    run_with_spinner sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    run_with_spinner sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
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
# If the active data directory doesn't exist but a backup exists, restore it.
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
    run_with_spinner sudo rm -rf "$backup_dir"
    run_with_spinner sudo mv "$data_dir" "$backup_dir"
    backup_required=true
else
    echo "${RED}Data directory not found at $data_dir; skipping backup.${RESET}"
fi
echo

########################################
# ghcr.io Login (Skip Explanation if Credentials Exist)
########################################
if [ -f ~/.docker/config.json ]; then
    echo "${GREEN}Existing Docker credentials found; skipping ghcr.io login.${RESET}"
else
    echo "${GREEN}Please log in to ghcr.io (GitHub Container Registry).${RESET}"
    attempt=1
    logged_in=false
    while [ $attempt -le 3 ]; do
        echo "Login Attempt $attempt (input from TTY):"
        if sudo docker login ghcr.io < /dev/tty; then
            logged_in=true
            break
        else
            echo "${RED}Attempt $attempt failed.${RESET}"
        fi
        attempt=$((attempt + 1))
    done

    if [ "$logged_in" != "true" ]; then
        echo "${RED}ghcr.io login failed after 3 attempts. Exiting.${RESET}"
        exit 1
    fi
    echo "${GREEN}ghcr.io login successful.${RESET}"
fi
echo

########################################
# Skip Credential Helper
########################################
echo "${YELLOW}Skipping credential helper; storing credentials in plain text.${RESET}"
echo

########################################
# Checking Immich Server Image
########################################
if sudo docker images ghcr.io/immich-app/immich-server:release >/dev/null 2>&1; then
    echo "${GREEN}Immich server image found locally.${RESET}"
else
    echo "${YELLOW}Pulling Immich server image from ghcr.io...${RESET}"
    run_with_spinner sudo docker pull ghcr.io/immich-app/immich-server:release
fi
echo

########################################
# Container Status & Health
########################################
if sudo docker ps --filter=name=immich_server --filter=status=running | grep -q immich_server; then
    echo "${GREEN}Immich container is running.${RESET}"
else
    echo "${RED}Immich container not running; attempting restart...${RESET}"
    { 
      run_with_spinner sudo docker rm -f immich_server 2>/dev/null
      run_with_spinner sudo docker restart immich_server
      sleep 5
    } || echo "${RED}Warning: Failed to restart Immich container. Continuing...${RESET}"
fi

health=$(sudo docker inspect --format="{{.State.Health.Status}}" immich_server 2>/dev/null || echo "unknown")
echo "Immich container health status: $health"
echo

########################################
# Watchtower & System Updates
########################################
echo "${YELLOW}Updating packages on Fedora...${RESET}"
run_with_spinner sudo dnf update -y

echo "${YELLOW}Installing Watchtower for container auto-updates...${RESET}"
if sudo docker ps -a --filter=name=watchtower | grep -qi watchtower; then
    run_with_spinner sudo docker rm -f watchtower
fi
run_with_spinner sudo docker run -d --name watchtower --restart always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower --schedule "0 0 * * *" --cleanup --include-restarting
echo

########################################
# Security Updates (dnf-automatic)
########################################
echo "${YELLOW}Configuring security updates...${RESET}"
run_with_spinner sudo dnf install -y dnf-automatic
sudo sed -i "s/^upgrade_type = .*/upgrade_type = security/" /etc/dnf/automatic.conf
sudo sed -i "s/^apply_updates = .*/apply_updates = yes/" /etc/dnf/automatic.conf
sudo sed -i "s/^reboot = .*/reboot = True/" /etc/dnf/automatic.conf
sudo mkdir -p /etc/systemd/system/dnf-automatic.timer.d
echo -e "[Timer]\nOnCalendar=*-*-* 03:00:00" | sudo tee /etc/systemd/system/dnf-automatic.timer.d/override.conf
sudo systemctl daemon-reload
sudo systemctl enable --now dnf-automatic.timer
echo "${GREEN}dnf-automatic is set for 3 AM security updates.${RESET}"
echo

########################################
# Monthly Full System Updates
########################################
echo "${YELLOW}Setting up monthly full system updates...${RESET}"
sudo tee /etc/systemd/system/full-update.service >/dev/null <<'EOF'
[Unit]
Description=Full System Update Service

[Service]
Type=oneshot
ExecStart=/usr/bin/dnf upgrade -y
EOF

sudo tee /etc/systemd/system/full-update.timer >/dev/null <<'EOF'
[Unit]
Description=Timer for Full System Update Service

[Timer]
OnCalendar=*-*-01 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now full-update.timer
echo "${GREEN}Full system update timer set for Fedora at 4 AM on the 1st of each month.${RESET}"
echo

########################################
# Restore Immich Data (if backup was made)
########################################
if [ "${backup_required:-false}" = true ]; then
    echo "${YELLOW}Restoring Immich data directory from backup...${RESET}"
    run_with_spinner sudo mv "$backup_dir" "$data_dir"
    sudo docker start immich_server
    echo "${GREEN}Immich data directory restored.${RESET}"
fi
echo

########################################
# Final Short Summary
########################################
echo "${GREEN}=== Short Summary ===${RESET}"
short_report="Immich Setup Complete.
Docker installed and running.
Immich container health: $health
Watchtower installed for auto-updates.
Security updates configured.
Monthly full system update scheduled."
echo "$short_report"
echo "${GREEN}=== Setup Complete ===${RESET}"
