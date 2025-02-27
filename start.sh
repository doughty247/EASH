#!/usr/bin/env bash
# Version: 1.1.11 Stable Release
# Last Updated: 2025-02-26
# Description: EASY - Effortless Automated Self-hosting for You
# This script checks that you're on Fedora, installs required tools,
# clones/updates the EASY repo (using sudo rm -rf to remove any old copy),
# dynamically builds a checklist based on all files in the EASY directory
# that end with "_setup.sh". In the checklist, the displayed names have the
# suffix removed, underscores replaced with spaces, and each word capitalized.
# After the checklist, an "Advanced Options" dialog appears with a toggle for
# "Show Output" (default off). Selected sub-scripts are then run sequentially;
# if "Show Output" is enabled, each script's output is printed; otherwise,
# output is suppressed. Before each subscript runs, the terminal (and its scrollback)
# is fully cleared. After all selected scripts have been executed, a TUI message box is shown.
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
    cd "$HOME"  # Move out of the repository to avoid removal issues.
    sudo rm -rf "$TARGET_DIR"
    git clone "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"

########################################
# Function to convert a filename into a display name:
# - Remove the suffix "_setup.sh"
# - Replace underscores with spaces
# - Capitalize each word
########################################
to_title() {
    local base="${1%_setup.sh}"
    local spaced
    spaced=$(echo "$base" | tr '_' ' ')
    echo "$spaced" | sed -r 's/(^| )(.)/\1\u\2/g'
}

########################################
# Dynamically build checklist from files ending with _setup.sh
########################################
declare -A SCRIPT_MAPPING  # Maps display name to actual script filename
display_names=()

for script in *_setup.sh; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        display_names+=("$(to_title "$script")")
        SCRIPT_MAPPING["$(to_title "$script")"]="$script"
    fi
done

if [ "${#display_names[@]}" -eq 0 ]; then
    dialog --msgbox "No setup scripts found in the directory. Exiting." 6 50
    exit 1
fi

# Sort the display names alphabetically.
IFS=$'\n' sorted_display_names=($(sort <<<"${display_names[*]}"))
unset IFS

# Build checklist items with sequential option numbers.
checklist_items=()
declare -A OPTION_TO_NAME
option_counter=1
for name in "${sorted_display_names[@]}"; do
    checklist_items+=("$option_counter" "$name" "off")
    OPTION_TO_NAME["$option_counter"]="$name"
    ((option_counter++))
done

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
IFS=$'\n' sorted_options=($(sort -n <<<"${selected_options[*]}"))
unset IFS

########################################
# Advanced Options - Separate Toggle for "Show Output"
########################################
advanced_result=$(dialog --clear --backtitle "Advanced Options" \
  --title "Advanced Options" \
  --checklist "Select advanced options:" 8 60 1 \
  "SHOW_OUTPUT" "Display subscript output" off 3>&1 1>&2 2>&3)

if [[ "$advanced_result" == *"SHOW_OUTPUT"* ]]; then
    SHOW_OUTPUT=1
else
    SHOW_OUTPUT=0
fi

########################################
# Function to fully clear the terminal (including scrollback)
########################################
clear_screen() {
    clear && printf '\033[3J'
}

########################################
# Function to run a script:
# If SHOW_OUTPUT is enabled, print output directly.
# If disabled, run script silently.
# In either case, clear the terminal fully before and after, and wait for Enter.
########################################
run_script_live() {
    local script_file="$1"
    clear_screen
    echo "Running $(basename "$script_file" _setup.sh)..."
    echo "----------------------------------------"
    if [ "$SHOW_OUTPUT" -eq 1 ]; then
        stdbuf -oL ./"$script_file"
    else
        stdbuf -oL ./"$script_file" &>/dev/null
        echo "(Output hidden)"
    fi
    echo "----------------------------------------"
    echo "$(basename "$script_file" _setup.sh) completed."
    echo "Press Enter to continue..."
    read -r
    clear_screen
}

########################################
# Run each selected setup script sequentially
########################################
for opt in "${sorted_options[@]}"; do
    display_name="${OPTION_TO_NAME[$opt]}"
    script_file="${SCRIPT_MAPPING[$display_name]}"
    run_script_live "$script_file"
done

clear_screen
dialog --msgbox "All selected setup scripts have been executed." 6 50
clear_screen
