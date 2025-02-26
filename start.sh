#!/usr/bin/env bash
# Version: 0.0.4
# Last Updated: 2025-02-26
# Description: EASY - Effortless Automated Self-hosting for You
# This script checks that you're on Fedora, installs required tools,
# clones/updates the EASY repo, displays a checklist of setup options
# (Immich, Nextcloud, Auto Updates), and runs the selected sub-scripts
# in order (top to bottom) with live output updated every 0.5 seconds
# inside the TUI.

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

cd "$TARGET_DIR"

########################################
# Define setup scripts and their descriptions (what each app does)
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
        checklist_items+=("$option_counter" "${SETUP_SCRIPTS[$script]}" "off")
        SCRIPT_MAP["$option_counter"]="$script"
        ((option_counter++))
    fi
done

if [ "${#SCRIPT_MAP[@]}" -eq 0 ]; then
    dialog --msgbox "No setup scripts found. Exiting." 6 50
    exit 1
fi

########################################
# Display checklist using dialog
########################################
result=$(dialog --clear --backtitle "EASY Checklist" \
  --title "E.A.S.Y. - Effortless Automated Self-hosting for You" \
  --checklist "Select the setup options you want to run (they will execute from top to bottom):" \
  16 80 4 "${checklist_items[@]}" 3>&1 1>&2 2>&3)

if [ -z "$result" ]; then
    dialog --msgbox "No options selected. Exiting." 6 50
    exit 0
fi

IFS=' ' read -r -a selected_options <<< "$result"
IFS=$'\n' sorted=($(sort -n <<<"${selected_options[*]}"))
unset IFS

########################################
# Function to run a script with live output updating every line
# It runs the script with forced line buffering, and in a loop, every 0.5 seconds,
# it displays the last 20 lines of output in an infobox to simulate auto scrolling.
########################################
run_script_live() {
    local script_file="$1"
    local tmpfile
    tmpfile=$(mktemp)
    rm -f "$tmpfile" 2>/dev/null
    touch "$tmpfile"
    
    # Run the script in the background with forced line buffering
    stdbuf -oL ./"$script_file" >> "$tmpfile" 2>&1 &
    local script_pid=$!

    # Loop until the script finishes, updating the displayed output
    while kill -0 "$script_pid" 2>/dev/null; do
        # Get last 20 lines of output
        output=$(tail -n 20 "$tmpfile")
        dialog --infobox "$output" 20 80
        sleep 0.5
    done
    
    # After the script finishes, show final output
    dialog --tailbox "$tmpfile" 20 80
    rm -f "$tmpfile"
}

########################################
# Run each selected setup script in order (top to bottom)
########################################
for opt in "${sorted[@]}"; do
    script_file="${SCRIPT_MAP[$opt]}"
    if dialog --clear --title "$(basename "$script_file" .sh)" --yesno "${SETUP_SCRIPTS[$script_file]}\n\nProceed with this setup?" 10 70; then
        run_script_live "$script_file"
    else
        dialog --msgbox "Cancelled $(basename "$script_file" .sh)." 4 40
    fi
done

dialog --msgbox "All selected setup scripts have been executed." 6 50
