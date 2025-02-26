#!/usr/bin/env bash
set -euo pipefail

########################################
# Install Git if not already installed
########################################
if ! command -v git &>/dev/null; then
    echo "Git is not installed. Installing Git on Fedora..."
    sudo dnf install -y git
fi

########################################
# Install Dialog if not already installed (for TUI)
########################################
if ! command -v dialog &>/dev/null; then
    echo "Dialog is not installed. Installing Dialog on Fedora..."
    sudo dnf install -y dialog
fi

########################################
# Clone or update the repository containing our scripts
########################################
REPO_URL="https://github.com/doughty247/EASY.git"
TARGET_DIR="$HOME/EASY"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Cloning repository from ${REPO_URL} into ${TARGET_DIR}..."
    git clone "$REPO_URL" "$TARGET_DIR"
else
    echo "Repository found in ${TARGET_DIR}. Updating repository..."
    cd "$TARGET_DIR"
    git pull --rebase
fi

# Change directory to the repository
cd "$TARGET_DIR"

# Ensure the setup scripts are executable
chmod +x immich_setup.sh nextcloud_setup.sh auto_updates_setup.sh

# Debug info: show current directory contents
echo "Current directory: $(pwd)"
echo "Listing files:"
ls -l
read -rp "Press Enter to continue..."

########################################
# EASY TUI Menu: Effortless Automated Self-hosting for You
########################################

# Temporary file for capturing dialog output
TEMP_FILE=$(mktemp)

# ANSI Colors and formatting for dialog messages
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
RED=$(tput setaf 1)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# Function to print the EASY header in ASCII art
print_header() {
  clear
  echo "${MAGENTA}${BOLD}"
  echo "    _____    _    ______   __"
  echo "   | ____|  / \\  / ___\\ \\ / /"
  echo "   |  _|   / _ \\ \\___ \\\\ V /"
  echo "   | |___ / ___ \\ ___) || |"
  echo "   |_____/_/   \\_\\____/ |_|   "
  echo "   Effortless Automated Self-hosting for You"
  echo "${RESET}"
  echo
}

# Function to display the menu using dialog
show_menu() {
  dialog --clear --backtitle "EASY Menu" \
    --title "E.A.S.Y. - Effortless Automated Self-hosting for You" \
    --menu "Use the arrow keys to navigate. Select an option for more details." 16 80 4 \
    1 "Immich Setup: Installs and configures Immich on Fedora." \
    2 "Nextcloud Setup: Installs and configures Nextcloud on your server." \
    3 "Auto Updates Setup: Sets up Docker Watchtower and automatic system updates." \
    4 "Exit" 2>"$TEMP_FILE"
}

# Function to display a confirmation prompt for the selected option
confirm_choice() {
  local title="$1"
  local description="$2"
  dialog --clear --title "$title" \
    --yesno "$description\n\nProceed with this setup?" 10 70
}

while true; do
  show_menu
  choice=$(<"$TEMP_FILE")
  case "$choice" in
    1)
      if confirm_choice "Immich Setup" "This script installs and configures Immich via Docker Compose on Fedora.
It downloads the latest docker-compose file and example environment file, and sets up the Immich container."; then
          if [[ -x "./immich_setup.sh" ]]; then
              dialog --infobox "Running Immich Setup..." 4 50
              ./immich_setup.sh
          else
              dialog --msgbox "Error: immich_setup.sh not found or not executable." 6 50
          fi
      else
          dialog --msgbox "Cancelled Immich Setup." 4 40
      fi
      ;;
    2)
      if confirm_choice "Nextcloud Setup" "This script installs and configures Nextcloud on your server.
It uses Docker Compose to set up Nextcloud with your desired configuration."; then
          if [[ -x "./nextcloud_setup.sh" ]]; then
              dialog --infobox "Running Nextcloud Setup..." 4 50
              ./nextcloud_setup.sh
          else
              dialog --msgbox "Error: nextcloud_setup.sh not found or not executable." 6 50
          fi
      else
          dialog --msgbox "Cancelled Nextcloud Setup." 4 40
      fi
      ;;
    3)
      if confirm_choice "Auto Updates Setup" "This script configures Docker Watchtower and sets up automatic system updates on Fedora.
It uses dnf-automatic for daily security updates and schedules monthly full system upgrades."; then
          if [[ -x "./auto_updates_setup.sh" ]]; then
              dialog --infobox "Running Auto Updates Setup..." 4 50
              ./auto_updates_setup.sh
          else
              dialog --msgbox "Error: auto_updates_setup.sh not found or not executable." 6 50
          fi
      else
          dialog --msgbox "Cancelled Auto Updates Setup." 4 40
      fi
      ;;
    4)
      dialog --msgbox "Exiting. Have a great day!" 4 40
      rm -f "$TEMP_FILE"
      clear
      exit 0
      ;;
    *)
      dialog --msgbox "Invalid option. Please try again." 4 40
      ;;
  esac
done
