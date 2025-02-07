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
    # Temporarily disable exit on error for the installation block.
    set +e
    sudo dnf upgrade -y
    sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest* docker-logrotate docker-engine
    sudo dnf -y install dnf-plugins-core

    # Instead of using 'dnf config-manager', create the Docker repo file manually.
    sudo tee /etc/yum.repos.d/docker-ce.repo >/dev/null <<'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/fedora/$releasever/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg
EOF

    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl start docker
    sudo systemctl enable docker
    # Re-enable exit on error.
    set -e
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
    wget -q -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
    wget -q -O .env https://github.com/immich-app/immich/releases/latest/download/example.env
    echo "${YELLOW}Starting Immich (timeout 30s)...${RESET}"
    timeout 30 sudo docker compose up -d || { echo "${RED}docker compose up timed out. Exiting.${RESET}"; exit 1; }
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
    sudo mv "$data_dir" "$backup_dir"
    backup_required=true
else
    echo "${RED}Data directory not found at $data_dir; skipping backup.${RESET}"
fi
echo

########################################
# ghcr.io Login (if no credentials exist)
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
    sudo docker pull ghcr.io/immich-app/immich-server:release
fi
echo

########################################
# Container Status & Health (Restart with Checks)
########################################
attempt=1
max_attempts=2
while [ $attempt -le $max_attempts ]; do
    echo "${YELLOW}Waiting 30 seconds for Immich container to start...${RESET}"
    sleep 30
    total_wait=0
    healthy_found=false
    while [ $total_wait -lt 120 ]; do
        if sudo docker ps --filter=name=immich_server --filter=status=running | grep -q immich_server; then
            healthy=$(sudo docker inspect --format="{{.State.Health.Status}}" immich_server 2>/dev/null || echo "unknown")
            if [ "$healthy" = "healthy" ]; then
                healthy_found=true
                break
            fi
        fi
        sleep 5
        total_wait=$((total_wait + 5))
    done
    if [ "$healthy_found" = true ]; then
        echo "${GREEN}Immich container is running and healthy.${RESET}"
        break
    else
        echo "${RED}Immich container did not become healthy after 2 minutes on attempt $attempt. Restarting container...${RESET}"
        sudo docker restart immich_server
        sleep 5
    fi
    attempt=$((attempt + 1))
done

if ! sudo docker ps --filter=name=immich_server --filter=status=running | grep -q immich_server; then
    echo "${RED}Immich container is still not running after retry attempts. Reinstalling Immich...${RESET}"
    # Reinstall Immich:
    cd ~/immich || exit 1
    sudo docker compose down --volumes --remove-orphans
    sudo docker rm -f immich_server 2>/dev/null
    sudo docker rmi ghcr.io/immich-app/immich-server:release 2>/dev/null
    echo "${YELLOW}Reinstalling Immich...${RESET}"
    timeout 30 sudo docker compose up -d || { echo "${RED}docker compose up timed out. Exiting.${RESET}"; exit 1; }
    # Start over: re-run the script.
    echo "${RED}Reinstallation complete but container still not healthy. Restarting setup script...${RESET}"
    exec "$0"
fi

health=$(sudo docker inspect --format="{{.State.Health.Status}}" immich_server 2>/dev/null || echo "unknown")
echo "Immich container health status: $health"
echo

########################################
# Watchtower & System Updates
########################################
echo "${YELLOW}Updating packages on Fedora...${RESET}"
sudo dnf update -y

echo "${YELLOW}Installing Watchtower for container auto-updates...${RESET}"
if sudo docker ps -a --filter=name=watchtower | grep -qi watchtower; then
    sudo docker rm -f watchtower
fi
sudo docker run -d --name watchtower --restart always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower --schedule "0 0 * * *" --cleanup --include-restarting
echo

########################################
# Security Updates (dnf-automatic)
########################################
echo "${YELLOW}Configuring security updates...${RESET}"
sudo dnf install -y dnf-automatic
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
    sudo mv "$backup_dir" "$data_dir"
    sudo docker start immich_server
    echo "${GREEN}Immich data directory restored.${RESET}"
fi
echo

########################################
# Final Status Report
########################################
echo "${GREEN}=== Status Report ===${RESET}"
status_report="Immich Setup Complete.
Docker is installed and running.
Immich container health: $health.
Watchtower is installed for auto-updates.
Security updates are configured.
Monthly full system updates are scheduled."
echo "$status_report"
echo "${GREEN}=== Setup Complete ===${RESET}"
