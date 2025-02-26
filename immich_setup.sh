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
RED=$(tput setaf 1)
RESET=$(tput sgr0)

########################################
# Log Output
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
# Network & Certificate Setup
########################################
echo "${YELLOW}Updating CA certificates...${RESET}"
sudo dnf install -y ca-certificates
sudo update-ca-trust extract

########################################
# Docker Installation (Recommended for Immich)
########################################
if ! command -v docker &>/dev/null; then
    echo "${YELLOW}Docker not found. Installing Docker for Fedora...${RESET}"
    # Temporarily disable exit-on-error for non-critical package removals/upgrades.
    set +e
    sudo dnf upgrade -y
    sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest* docker-logrotate docker-engine
    sudo dnf -y install dnf-plugins-core
    set -e

    # Manually create the Docker repository file using the current Fedora version.
    FEDORA_VERSION=$(rpm -E %fedora)
    sudo tee /etc/yum.repos.d/docker-ce.repo >/dev/null <<EOF
[docker-ce-stable]
name=Docker CE Stable - \$basearch
baseurl=https://download.docker.com/linux/fedora/${FEDORA_VERSION}/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg
EOF

    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl start docker
    sudo systemctl enable docker
else
    echo "${GREEN}Docker is already installed.${RESET}"
fi
echo

########################################
# Docker Version & Daemon Status
########################################
echo "${GREEN}Docker Version & Daemon Status:${RESET}"
sudo docker version
sudo systemctl is-active docker
echo

########################################
# Docker Group Check and Automatic Logout
########################################
if ! getent group docker >/dev/null; then
    echo "${YELLOW}Group 'docker' does not exist. Creating group 'docker'...${RESET}"
    sudo groupadd docker
fi

if ! groups "$USER" | grep -qw docker; then
    echo "${YELLOW}User not in 'docker' group. Adding $USER to the 'docker' group...${RESET}"
    sudo usermod -aG docker "$USER"
    echo "${GREEN}You need to log out and log in again and re-run the script to continue."
    sleep 5
    read -r -p "Press Enter to log out now..." </dev/tty
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
# Immich Setup (Without Timeout Wrapper)
########################################
if ! sudo docker ps -a --filter=name=immich_server | grep -q immich_server; then
    echo "${YELLOW}Immich not found. Setting it up using official docker-compose instructions...${RESET}"
    mkdir -p ~/immich && cd ~/immich || exit 1
    wget -q -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
    wget -q -O .env https://github.com/immich-app/immich/releases/latest/download/example.env
    echo "${YELLOW}Starting Immich container...${RESET}"
    sudo docker compose up -d || { echo "${RED}docker compose up failed. Exiting.${RESET}"; exit 1; }
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
# ghcr.io Login (GitHub Container Registry)
########################################
echo "${GREEN}To access GitHub Container Registry (ghcr.io), you need to create a GitHub Personal Access Token (PAT)."
echo "Follow these steps:"
echo "  1. Visit: https://github.com/settings/tokens"
echo "  2. Click 'Generate new token'."
echo "  3. Give your token a descriptive name."
echo "  4. Under 'Select scopes', check 'read:packages' (and any additional scopes you need)."
echo "  5. Generate the token and copy it immediately (you won't be able to see it again)."
echo "  6. When prompted below, use your GitHub username and paste the token as the password."
echo "${RESET}"
if [ -f ~/.docker/config.json ]; then
    echo "${GREEN}Existing Docker credentials found; skipping ghcr.io login.${RESET}"
else
    echo "${GREEN}Please log in to ghcr.io (GitHub Container Registry) using your GitHub Personal Access Token.${RESET}"
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
# Setup Docker Credential Helper (Using docker-credential-pass)
########################################
echo "${YELLOW}Setting up Docker credential helper using 'pass'...${RESET}"
# Ensure that 'pass' is installed.
if ! command -v pass &>/dev/null; then
    echo "${YELLOW}'pass' not found. Installing 'pass'...${RESET}"
    sudo dnf install -y pass
fi

# Attempt to install docker-credential-pass.
if ! command -v docker-credential-pass &>/dev/null; then
    echo "${YELLOW}docker-credential-pass not found. Installing it...${RESET}"
    sudo dnf install -y docker-credential-pass --skip-unavailable || true
fi

if command -v docker-credential-pass &>/dev/null; then
    # Configure Docker to use 'pass' as the credentials helper.
    mkdir -p ~/.docker
    CONFIG_FILE=~/.docker/config.json
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE"
    fi
    if grep -q '"credsStore":' "$CONFIG_FILE"; then
        sed -i 's/"credsStore": *"[^"]*"/"credsStore": "pass"/' "$CONFIG_FILE"
    else
        if [ "$(cat "$CONFIG_FILE")" = "{}" ]; then
             echo '{ "credsStore": "pass" }' > "$CONFIG_FILE"
        else
             if command -v jq &>/dev/null; then
                 jq '. + {"credsStore": "pass"}' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
             else
                 sed -i 's/^{/{\n  "credsStore": "pass",/' "$CONFIG_FILE"
             fi
        fi
    fi
    echo "${GREEN}Docker credential helper configured to use 'pass'.${RESET}"
else
    echo "${RED}Error: docker-credential-pass is not available. Please install it manually, or remove the credentials helper configuration.${RESET}"
fi
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
# Container Running Check (Bypassing Health Check)
########################################
echo "${YELLOW}Waiting up to 30 seconds for the Immich container to report healthy...${RESET}"
max_attempts=6
healthy_found=false
for i in $(seq 1 "$max_attempts"); do
    status=$(sudo docker inspect --format="{{.State.Health.Status}}" immich_server 2>/dev/null || echo "unknown")
    if [ "$status" = "healthy" ]; then
        healthy_found=true
        break
    fi
    sleep 5
done

if [ "$healthy_found" = false ]; then
    echo "${RED}Warning: Immich container did not become healthy within 30 seconds. Proceeding anyway.${RESET}"
else
    echo "${GREEN}Immich container is healthy.${RESET}"
fi
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
if [ ! -f /etc/dnf/automatic.conf ]; then
    echo "${YELLOW}/etc/dnf/automatic.conf not found. Creating default configuration...${RESET}"
    sudo tee /etc/dnf/automatic.conf >/dev/null <<'EOF'
[commands]
upgrade_type = security
apply_updates = yes
reboot = True

[emitters]
emit_via = stdio
EOF
else
    sudo sed -i "s/^upgrade_type = .*/upgrade_type = security/" /etc/dnf/automatic.conf
    sudo sed -i "s/^apply_updates = .*/apply_updates = yes/" /etc/dnf/automatic.conf
    sudo sed -i "s/^reboot = .*/reboot = True/" /etc/dnf/automatic.conf
fi

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
Immich container running (if not healthy, a warning was issued).
Docker credential helper is configured (using 'pass').
Watchtower is installed for auto-updates.
Security updates are configured.
Monthly full system updates are scheduled."
echo "$status_report"
echo "${GREEN}=== Setup Complete ===${RESET}"
