#!/usr/bin/env bash
set -euo pipefail

# Request sudo permission upfront
sudo -v

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
    sudo rm -rf "$TARGET_DIR"
    git clone "$REPO_URL" "$TARGET_DIR"
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
# Build the dynamic checklist and set executable permissions
########################################
checklist_items=()
declare -A SCRIPT_MAP  # maps option number to script filename
option_counter=1

for script in "${!SETUP_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        # Add the option with a default "off" state.
        checklist_items+=("$option_counter" "${SETUP_SCRIPTS[$script]}" "off")
        SCRIPT_MAP["$option_counter"]="$script"
        ((option_counter++))
    fi
done

# If no setup scripts found, exit.
if [ "${#SCRIPT_MAP[@]}" -eq 0 ]; then
    echo "No setup scripts found. Exiting."
    exit 1
fi

########################################
# Display a checklist for all options using dialog
########################################
result=$(dialog --clear --backtitle "EASY Checklist" \
  --title "E.A.S.Y. - Effortless Automated Self-hosting for You" \
  --checklist "Select the setup options you want to run:" \
  16 80 4 "${checklist_items[@]}" 2>&1 >/dev/tty)

# If user cancels or nothing selected, exit.
if [ -z "$result" ]; then
    echo "No options selected. Exiting."
    exit 0
fi

# The result is a space-separated list of selected option numbers (e.g., "1 3")
# We sort them numerically so they run in the order they appear in the checklist.
IFS=' ' read -r -a selected_options <<< "$result"
IFS=$'\n' sorted=($(sort -n <<<"${selected_options[*]}"))
unset IFS

########################################
# Run each selected setup script in order (top to bottom)
########################################
for opt in "${sorted[@]}"; do
    script_file="${SCRIPT_MAP[$opt]}"
    echo "Running $(basename "$script_file" .sh)..."
    # Run the script in a subshell so that control returns even if it exits.
    ( ./"$script_file" )
    echo "Completed $(basename "$script_file" .sh)."
    read -rp "Press Enter to continue to the next option..."
done

echo "All selected setup scripts have been executed."
