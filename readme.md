# Immich Setup Script for Fedora

This Bash script automates the installation and configuration of [Immich](https://immich.app/) (a self-hosted photo/video management solution) on Fedora. It performs OS checks, installs Docker & Docker Compose (if needed), deploys Immich via Docker, and sets up automated updates and backups.

## Features

- **Fedora Detection:** Ensures the script runs only on Fedora.
- **Docker Installation:** Installs Docker, sets up the Docker group, and verifies the daemon.
- **Immich Deployment:** Downloads the official `docker-compose.yml` and `.env`, then starts Immich.
- **Data Safety:** Backs up and restores the Immich data directory.
- **Automated Maintenance:** Configures Watchtower for container updates and uses `dnf-automatic` for system updates.
- **Secure Credentials:** Prompts for GitHub Container Registry login and sets up a Docker credential helper.

## Prerequisites

- Fedora OS with sudo privileges
- Network access for downloading packages and container images

## Installation & Usage

/// curl -L -s https://raw.githubusercontent.com/doughty247/immichsetup/refs/heads/main/setup.sh | bash
   