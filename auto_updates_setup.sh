#!/usr/bin/env bash
set -euo pipefail

# ANSI Colors
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

echo "${GREEN}Starting Watchtower and Auto System Updates Setup...${RESET}"
echo

########################################
# Update Packages on Fedora
########################################
echo "${YELLOW}Updating Fedora packages...${RESET}"
sudo dnf update -y
echo

########################################
# Watchtower Setup for Docker Container Auto-Updates
########################################
echo "${YELLOW}Setting up Watchtower for container auto-updates...${RESET}"
if sudo docker ps -a --filter=name=watchtower | grep -qi watchtower; then
    echo "${YELLOW}Removing existing Watchtower container...${RESET}"
    sudo docker rm -f watchtower
fi
sudo docker run -d --name watchtower --restart always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower --schedule "0 0 * * *" --cleanup --include-restarting
echo "${GREEN}Watchtower setup complete.${RESET}"
echo

########################################
# Configure Security Updates via dnf-automatic
########################################
echo "${YELLOW}Configuring security updates with dnf-automatic...${RESET}"
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
echo -e "[Timer]\nOnCalendar=*-*-* 03:00:00" | sudo tee /etc/systemd/system/dnf-automatic.timer.d/override.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now dnf-automatic.timer
echo "${GREEN}dnf-automatic is configured for daily 3 AM security updates.${RESET}"
echo

########################################
# Setup Monthly Full System Updates
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
echo "${GREEN}Monthly full system update timer set for 4 AM on the 1st of each month.${RESET}"
echo

echo "${GREEN}Watchtower and auto system updates setup complete.${RESET}"
