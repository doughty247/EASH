#!/usr/bin/env bash
set -euo pipefail

########################################
# Check if OS is Fedora
########################################
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "fedora" ]; then
        echo "Sorry, this script is designed for Fedora only."
        exit 1
    fi
else
    echo "OS detection failed. This script is designed for Fedora only."
    exit 1
fi

# Request sudo permission upfront
sudo -v

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

########################################
# Define setup scripts and their descriptions (about what the app does)
########################################
declare -A SETUP_SCRIPTS
SETUP_SCRIPTS["immich_setup.sh"]="Immich: Self-hosted photo & video backup & management."
SETUP_SCRIPTS["nextcloud_setup.sh"]="Nextcloud: Self-hosted file sync & share for secure storage."
SETUP_SCRIPTS["auto_updates_setup.sh"]="Auto Updates: Automatically updates your container apps and applies security patches."

########################################
# Build the dynamic menu and set executable permissions
########################################
menu_items=()
declare -A SCRIPT_MAP  # maps option number to script filename
option_counter=1

for script in "${!SETUP_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        menu_items+=("$option_counter" "${SETUP_SCRIPTS[$script]}")
        SCRIPT_MAP["$option_counter"]="$script"
        ((option_counter++))
    fi
done

# Always add the exit option
menu_items+=("$option_counter" "Exit")
EXIT_OPTION="$option_counter"

# Debug info: show current directory contents
echo "Current directory: $(pwd)"
echo "Listing files:"
ls -l
read -rp "Press Enter to continue..."

########################################
# TUI Menu using Dialog: EASY (Effortless Automated Self-hosting for You)
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

# Function to print the EASY header in ASCII art (for non-dialog output)
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

# Function to display the menu using Dialog
show_menu() {
  dialog --clear --backtitle "EASY Menu" \
    --title "E.A.S.Y. - Effortless Automated Self-hosting for You" \
    --menu "Use the arrow keys to navigate. Select an option for more details." 16 80 4 \
    "${menu_items[@]}" 2>"$TEMP_FILE"
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
  if [ "$choice" == "$EXIT_OPTION" ]; then
    dialog --msgbox "Exiting. Have a great day!" 4 40
    rm -f "$TEMP_FILE"
    clear
    exit 0
  elif [[ -n "${SCRIPT_MAP[$choice]:-}" ]]; then
    script_file="${SCRIPT_MAP[$choice]}"
    confirm_choice "$(basename "$script_file" .sh)" "${SETUP_SCRIPTS[$script_file]}"
    if [ $? -eq 0 ]; then
      dialog --infobox "Running $(basename "$script_file" .sh)..." 4 50
      ./"$script_file"
    else
      dialog --msgbox "Cancelled $(basename "$script_file" .sh)." 4 40
    fi
  else
    dialog --msgbox "Invalid option. Please try again." 4 40
  fi
done
