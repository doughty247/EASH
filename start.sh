#!/usr/bin/env bash
set -euo pipefail

########################################
# Ensure Git is installed on Fedora
########################################
if ! command -v git &>/dev/null; then
    echo "Git is not installed. Installing Git on Fedora..."
    sudo dnf install -y git
fi

########################################
# Ensure Dialog is installed for TUI
########################################
if ! command -v dialog &>/dev/null; then
    echo "Dialog is not installed. Installing Dialog on Fedora..."
    sudo dnf install -y dialog
fi

########################################
# Clone or update the repository containing our scripts
########################################
# Set your repository URL here (update as needed)
REPO_URL="https://github.com/doughty247/EASY.git"
# Set the target directory where the repository will be cloned
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

########################################
# EASY TUI Menu (Effortless Automated Self-hosting for You)
########################################

# Temporary file for capturing dialog output
TEMP_FILE=$(mktemp)

# Function to display the main menu using dialog
show_menu() {
  dialog --clear --backtitle "EASY Menu" \
    --title "E.A.S.Y. - Effortless Automated Self-hosting for You" \
    --menu "Use arrow keys to navigate. When you select an option, a description will be shown for confirmation." 15 70 4 \
    1 "Immich Setup: Installs and configures Immich via Docker Compose on Fedora." \
    2 "Auto Updates Setup: Configures Docker Watchtower and automatic system updates." \
    3 "Nextcloud Setup: Installs and configures Nextcloud on your server." \
    4 "Exit" 2>"$TEMP_FILE"
}

# Function to display a confirmation message for a given option
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
      if confirm_choice "Immich Setup" "This script installs and configures Immich on Fedora using Docker Compose."; then
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
      if confirm_choice "Auto Updates Setup" "This script configures Docker Watchtower and sets up automatic system updates (dnf-automatic and monthly full updates) on Fedora."; then
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
    3)
      if confirm_choice "Nextcloud Setup" "This script installs and configures Nextcloud on your server."; then
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
