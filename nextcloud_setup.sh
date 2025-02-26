#!/usr/bin/env bash
# Version: 1.1.8
# Last Updated: 2025-02-26
# Description: EASY - Effortless Automated Self-hosting for You
# This script checks that you're on Fedora, installs required tools,
# clones/updates the EASY repo (using sudo rm -rf to remove any old copy),
# dynamically builds a checklist based on all files in the EASY directory
# that end with "_setup.sh" (with no descriptions), and runs the selected
# sub-scripts sequentially. Before running each subscript, the terminal (and its
# scrollback) is fully cleared. After all selected scripts have been executed,
# a TUI message box is shown.
#
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
    cd "$HOME"                # move out of the repository directory
    sudo rm -rf "$TARGET_DIR"
    git clone "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"

########################################
# Dynamically build checklist from files ending with _setup.sh
########################################
checklist_items=()
declare -A SCRIPT_MAP
option_counter=1

for script in *_setup.sh; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        checklist_items+=("$option_counter" "$script" "off")
        SCRIPT_MAP["$option_counter"]="$script"
        ((option_counter++))
    fi
done

if [ "${#SCRIPT_MAP[@]}" -eq 0 ]; then
    dialog --msgbox "No setup scripts found in the directory. Exiting." 6 50
    exit 1
fi

########################################
# Display dynamic checklist using dialog
########################################
result=$(dialog --clear --backtitle "EASY Checklist" \
  --title "E.A.S.Y. - Effortless Automated Self-hosting for You" \
  --checklist "Select the setup scripts you want to run (they will execute from top to bottom):" \
  16 80 4 "${checklist_items[@]}" 3>&1 1>&2 2>&3)

if [ -z "$result" ]; then
    dialog --msgbox "No options selected. Exiting." 6 50
    exit 0
fi

IFS=' ' read -r -a selected_options <<< "$result"
IFS=$'\n' sorted=($(sort -n <<<"${selected_options[*]}"))
unset IFS

########################################
# Function to fully clear the terminal (including scrollback)
########################################
clear_screen() {
    clear && printf '\033[3J'
}

########################################
# Function to run a script with its output printed directly.
# Clears the terminal fully before running the subscript,
# then waits for user input and clears again.
########################################
run_script_live() {
    local script_file="$1"
    clear_screen
    echo "Running $(basename "$script_file" .sh)..."
    echo "----------------------------------------"
    stdbuf -oL ./"$script_file"
    echo "----------------------------------------"
    echo "$(basename "$script_file" .sh) completed."
    echo "Press Enter to continue..."
    read -r
    clear_screen
}

########################################
# Run each selected setup script sequentially
########################################
for opt in "${sorted[@]}"; do
    script_file="${SCRIPT_MAP[$opt]}"
    run_script_live "$script_file"
done

clear_screen
dialog --msgbox "All selected setup scripts have been executed." 6 50
clear_screen
