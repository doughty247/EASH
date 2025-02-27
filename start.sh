#!/usr/bin/env bash
# Version: 1.1.13 Stable Release
# Last Updated: 2025-02-26
# Description: EASY - Effortless Automated Self-hosting for You
# This script checks that you're on Fedora, installs required tools,
# clones/updates the EASY repo (using sudo rm -rf to remove any old copy),
# dynamically builds a checklist based on all files in the EASY directory
# that end with "_setup.sh". In the checklist, the displayed names have the
# suffix removed, underscores replaced with spaces, and each word capitalized.
# The main checklist includes an advanced toggle for "Show Output" (default off).
# The selected sub-scripts are then run sequentially. Before each sub-script,
# the terminal (and its scrollback) is fully cleared.
# If "Show Output" is off, subscript output is hidden and a progress spinner is
# shown whenever a line indicating a download command ("dnf" or "docker") is detected.
# After each script, an overall progress indicator ("Progress: X/Y scripts executed")
# is printed at the bottom, and finally a TUI message box confirms completion.
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
    cd "$HOME"  # move out of repository before removal
    sudo rm -rf "$TARGET_DIR"
    git clone "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"

########################################
# Function to convert filename to display name:
# - Remove suffix "_setup.sh"
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
        title=$(to_title "$script")
        display_names+=("$title")
        SCRIPT_MAPPING["$title"]="$script"
    fi
done

if [ "${#display_names[@]}" -eq 0 ]; then
    dialog --msgbox "No setup scripts found in the directory. Exiting." 6 50
    exit 1
fi

# Sort display names alphabetically.
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

# Append advanced option toggle for "Show Output"
advanced_tag="ADV_SHOW_OUTPUT"
advanced_label="Show Output"
checklist_items+=("$advanced_tag" "$advanced_label" "off")

########################################
# Display main checklist using dialog (Advanced option included)
########################################
result=$(dialog --clear --backtitle "EASY Checklist" \
  --title "E.A.S.Y. - Effortless Automated Self-hosting for You" \
  --checklist "Select the setup scripts you want to run (they will execute from top to bottom):" \
  16 80 6 "${checklist_items[@]}" 3>&1 1>&2 2>&3)

if [ -z "$result" ]; then
    dialog --msgbox "No options selected. Exiting." 6 50
    exit 0
fi

# Process result: if ADV_SHOW_OUTPUT is selected, set SHOW_OUTPUT=1.
SHOW_OUTPUT=0
selected_numeric=()
IFS=' ' read -r -a selected_options <<< "$result"
for opt in "${selected_options[@]}"; do
    if [ "$opt" == "$advanced_tag" ]; then
        SHOW_OUTPUT=1
    else
        selected_numeric+=("$opt")
    fi
done
IFS=$'\n' sorted_options=($(sort -n <<<"${selected_numeric[*]}"))
unset IFS

########################################
# Function to fully clear the terminal (including scrollback)
########################################
clear_screen() {
    clear && printf '\033[3J'
}

########################################
# Spinner function for download activity (square-shaped)
# Runs for a fixed duration (5 seconds)
########################################
spinner_download() {
    local duration=5
    local start_time=$(date +%s)
    local spinner_frames=("■□□□□" "□■□□□" "□□■□□" "□□□■□" "□□□□■")
    local frame_count=${#spinner_frames[@]}
    while [ $(( $(date +%s) - start_time )) -lt $duration ]; do
        for ((i=0; i<frame_count; i++)); do
            dialog --infobox "Downloading... ${spinner_frames[$i]}" 3 30
            sleep 0.2
        done
    done
}

# Global flag to avoid multiple simultaneous spinners.
DOWNLOAD_SPINNER_RUNNING=0

########################################
# Function to run a script with overall progress indication.
# If SHOW_OUTPUT is enabled, output is shown normally.
# If disabled, output is hidden; additionally, if a line indicating a download
# (contains "dnf" or "docker") is detected, a secondary spinner is shown.
# After each script, overall progress ("Progress: X/Y scripts executed") is displayed.
########################################
run_script_live() {
    local script_file="$1"
    clear_screen
    echo "Running $(basename "$script_file" _setup.sh)..."
    echo "----------------------------------------"
    
    if [ "$SHOW_OUTPUT" -eq 1 ]; then
        stdbuf -oL ./"$script_file"
    else
        # Run script with trace and process output line-by-line.
        while IFS= read -r line; do
            # If line indicates a download, and spinner not running, start spinner.
            if [[ "$line" == *"dnf"* ]] || [[ "$line" == *"docker"* ]]; then
                if [ "$DOWNLOAD_SPINNER_RUNNING" -eq 0 ]; then
                    DOWNLOAD_SPINNER_RUNNING=1
                    spinner_download &
                    spinner_pid=$!
                    # Wait a short moment to simulate download progress.
                    sleep 1
                    kill $spinner_pid 2>/dev/null || true
                    DOWNLOAD_SPINNER_RUNNING=0
                fi
            fi
            # (Do not output the trace line when SHOW_OUTPUT is off)
        done < <(stdbuf -oL bash -x "$script_file")
        echo "(Output hidden)"
    fi
    
    echo "----------------------------------------"
    script_name=$(basename "$script_file" _setup.sh)
    echo "$script_name completed."
}

########################################
# Function to display overall progress
########################################
display_overall_progress() {
    local current=$1
    local total=$2
    local percent=$(( current * 100 / total ))
    dialog --gauge "Progress: Script $current of $total executed" 6 60 "$percent"
    sleep 1
    clear_screen
}

########################################
# Run each selected setup script sequentially and update overall progress
########################################
total_scripts=${#sorted_options[@]}
current=0
for opt in "${sorted_options[@]}"; do
    current=$((current+1))
    display_name="${OPTION_TO_NAME[$opt]}"
    script_file="${SCRIPT_MAPPING[$display_name]}"
    run_script_live "$script_file"
    display_overall_progress "$current" "$total_scripts"
    echo "Press Enter to continue to the next script..."
    read -r
done

clear_screen
dialog --msgbox "All selected setup scripts have been executed." 6 50
clear_screen
