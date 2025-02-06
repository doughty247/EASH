#!/usr/bin/env bash
set -euo pipefail

# Unset any custom DOCKER_HOST to ensure Docker uses the default socket.
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

echo "${GREEN}Starting Immich Setup Script...${RESET}"
echo

########################################
# OS Detection
########################################
if [ -f /etc/os-release ]; then
    . /etc/os-release
elif command -v lsb_release &>/dev/null; then
    ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    VERSION_ID=$(lsb_release -sr)
else
    echo "${RED}OS detection failed. Exiting.${RESET}"
    exit 1
fi

if [ "$ID" != "fedora" ] && [ "$ID" != "ubuntu" ]; then
    echo "${RED}Unsupported distro ($ID). Only fedora/ubuntu are supported.${RESET}"
    exit 1
fi

echo "${GREEN}Distro detected: $ID ($VERSION_ID)${RESET}"
echo

########################################
# Docker Group Check and Automatic Fix
########################################
if ! groups "$USER" | grep -qw docker; then
    echo "${YELLOW}You are not in the 'docker' group.${RESET}"
    echo "${YELLOW}Adding $USER to the 'docker' group...${RESET}"
    sudo usermod -aG docker "$USER"
    echo "${GREEN}Done. You must now log out and log back in for this to take effect."
    echo "${RED}Please log out, log back in, and re-run this script.${RESET}"
    exit 1
fi
echo

########################################
# Docker Installation
########################################
if ! command -v docker &>/dev/null; then
    echo "${YELLOW}Docker not found. Installing Docker for $ID...${RESET}"
    if [ "$ID" = "fedora" ]; then
        run_with_spinner sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest* docker-logrotate docker-engine || true
        run_with_spinner sudo dnf -y install dnf-plugins-core
        run_with_spinner sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        run_with_spinner sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker
    elif [ "$ID" = "ubuntu" ]; then
        export DEBIAN_FRONTEND=noninteractive
        run_with_spinner sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
        echo "${YELLOW}Running apt-get update...${RESET}"
        run_with_spinner sudo apt-get update
        echo "${YELLOW}Installing prerequisites...${RESET}"
        run_with_spinner sudo apt-get install -y ca-certificates curl gnupg lsb-release
        echo "${YELLOW}Adding Docker’s official GPG key...${RESET}"
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "${YELLOW}Setting up Docker repository...${RESET}"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
        echo "${YELLOW}Updating package list...${RESET}"
        run_with_spinner sudo apt-get update
        echo "${YELLOW}Installing Docker packages...${RESET}"
        run_with_spinner sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
else
    echo "${GREEN}Docker is already installed.${RESET}"
fi
echo

########################################
# Docker Version & Daemon Status
########################################
echo "${GREEN}Docker Version & Daemon Status:${RESET}"
docker version
systemctl is-active docker
echo

########################################
# Immich Setup
########################################
if ! docker ps -a --filter=name=immich_server | grep -q immich_server; then
    echo "${YELLOW}Immich not found. Setting it up using official docker-compose instructions...${RESET}"
    mkdir -p ~/immich && cd ~/immich || exit 1
    run_with_spinner wget -q -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
    run_with_spinner wget -q -O .env https://github.com/immich-app/immich/releases/latest/download/example.env
    echo "${YELLOW}Starting Immich (timeout 120s)...${RESET}"
    run_with_spinner timeout 120 docker compose up -d || { echo "${RED}docker compose up timed out. Exiting.${RESET}"; exit 1; }
    echo "${GREEN}Immich setup complete.${RESET}"
else
    echo "${GREEN}Immich container already exists; skipping setup.${RESET}"
fi
echo

########################################
# Protecting Immich Data
########################################
data_dir="./immich/library"
if [ -d "$data_dir" ]; then
    random_dir=$(printf "%06d" $((RANDOM % 1000000)))
    safe_dir="./${random_dir}"
    echo "${YELLOW}Moving $data_dir to $safe_dir, then moving it back (preserving permissions)...${RESET}"
    run_with_spinner sudo rm -rf "$safe_dir"
    run_with_spinner sudo mv "$data_dir" "$safe_dir"
    run_with_spinner sudo mv "$safe_dir" "$data_dir"
else
    echo "${RED}Data directory not found at $data_dir; skipping protection.${RESET}"
fi
echo

########################################
# ghcr.io Login
########################################
if [ ! -f ~/.docker/config.json ]; then
    echo "${YELLOW}No Docker credentials found.${RESET}"
else
    echo "${YELLOW}Existing Docker credentials found; leaving them.${RESET}"
fi

echo "${GREEN}Please log in to ghcr.io (GitHub Container Registry).${RESET}"
attempt=1
logged_in=false
while [ $attempt -le 3 ]; do
    echo "Login Attempt $attempt (input from TTY):"
    if docker login ghcr.io < /dev/tty; then
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
echo

########################################
# Skip Credential Helper
########################################
echo "${YELLOW}Skipping credential helper; storing credentials in plain text.${RESET}"
echo

########################################
# Checking Immich Server Image
########################################
if docker images ghcr.io/immich-app/immich-server:release >/dev/null 2>&1; then
    echo "${GREEN}Immich server image found locally.${RESET}"
else
    echo "${YELLOW}Pulling Immich server image from ghcr.io...${RESET}"
    run_with_spinner docker pull ghcr.io/immich-app/immich-server:release
fi
echo

########################################
# Container Status & Health
########################################
if docker ps --filter=name=immich_server --filter=status=running | grep -q immich_server; then
    echo "${GREEN}Immich container is running.${RESET}"
else
    echo "${RED}Immich container not running; attempting restart...${RESET}"
    run_with_spinner docker rm -f immich_server 2>/dev/null
    run_with_spinner docker restart immich_server
    sleep 5
fi

health=$(docker inspect --format="{{.State.Health.Status}}" immich_server 2>/dev/null || echo "unknown")
echo "Immich container health status: $health"
echo

########################################
# Watchtower & Updates
########################################
. /etc/os-release
if [ "$ID" = "fedora" ]; then
    echo "${YELLOW}Updating packages on Fedora...${RESET}"
    run_with_spinner sudo dnf update -y
elif [ "$ID" = "ubuntu" ]; then
    echo "${YELLOW}Updating packages on Ubuntu...${RESET}"
    run_with_spinner sudo apt-get update && sudo apt-get upgrade -y
fi

echo "${YELLOW}Installing Watchtower for container auto-updates...${RESET}"
if docker ps -a --filter=name=watchtower | grep -qi watchtower; then
    run_with_spinner docker rm -f watchtower
fi
run_with_spinner docker run -d --name watchtower --restart always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower --schedule "0 0 * * *" --cleanup --include-restarting
echo

########################################
# Security Updates
########################################
if [ "$ID" = "fedora" ]; then
    run_with_spinner sudo dnf install -y dnf-automatic
    sudo sed -i "s/^upgrade_type = .*/upgrade_type = security/" /etc/dnf/automatic.conf
    sudo sed -i "s/^apply_updates = .*/apply_updates = yes/" /etc/dnf/automatic.conf
    sudo sed -i "s/^reboot = .*/reboot = True/" /etc/dnf/automatic.conf
    sudo mkdir -p /etc/systemd/system/dnf-automatic.timer.d
    echo -e "[Timer]\nOnCalendar=*-*-* 03:00:00" | sudo tee /etc/systemd/system/dnf-automatic.timer.d/override.conf
    sudo systemctl daemon-reload
    sudo systemctl enable --now dnf-automatic.timer
    echo "${GREEN}dnf-automatic is set for 3 AM security updates.${RESET}"
elif [ "$ID" = "ubuntu" ]; then
    run_with_spinner sudo apt-get install -y unattended-upgrades
    sudo sed -i "s|//Unattended-Upgrade::Automatic-Reboot \"false\";|Unattended-Upgrade::Automatic-Reboot \"true\";|" /etc/apt/apt.conf.d/50unattended-upgrades
    ( sudo crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/unattended-upgrade -d" ) | sudo crontab -
    echo "${GREEN}unattended-upgrades is set for 3 AM security updates.${RESET}"
fi
echo

########################################
# Monthly Full System Updates
########################################
if [ "$ID" = "fedora" ]; then
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
elif [ "$ID" = "ubuntu" ]; then
    ( sudo crontab -l 2>/dev/null; echo "0 4 1 * * /usr/bin/apt-get update && /usr/bin/apt-get upgrade -y" ) | sudo crontab -
    echo "${GREEN}Monthly system update cron set for Ubuntu at 4 AM on the 1st of each month.${RESET}"
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
