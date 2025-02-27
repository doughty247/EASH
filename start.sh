#!/usr/bin/env bash
# Version: 1.1.15 Stable Release
# Last Updated: 2025-02-26
# Description: EASY - Effortless Automated Self-hosting for You
# This script checks that you're on Fedora, installs required tools,
# clones/updates the EASY repo (using sudo rm -rf to remove any old copy),
# and dynamically builds a checklist based on all files in the EASY directory
# ending with "_setup.sh". The displayed names have the suffix removed,
# underscores replaced with spaces, and each word capitalized.
#
# All subscript items are enabled by default.
# The main checklist includes an extra toggle "Enable Advanced Options" (default off).
# If that toggle is selected, a second dialog appears letting you toggle "Show Output" (default off).
# Once selections are made, the chosen subscripts are run sequentially.
# After running all subscripts, the script goes straight to displaying a final
# Installation Report showing a checklist of subscript names with checkboxes indicating success.
#
set -uo pipefail  # Do not use -e so failures in subscripts do not abort the main script

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
# Install Dialog if not already installed
########################################
if ! command -v dialog &>/dev/null; then
    echo "Dialog is not installed. Installing Dialog on Fedora..."
    sudo dnf install -y dialog
fi

########################################
# Clone or update the repository
########################################
REPO_URL="https://github.com/doughty247/EASY.git"
TARGET_DIR="$HOME/EASY"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Cloning repository from ${REPO_URL} into ${TARGET_DIR}..."
    git clone "$REPO_URL" "$TARGET_DIR"
else
    echo "Repository found in ${TARGET_DIR}. Updating repository..."
    cd "$HOME"  # Move out of repository directory
    sudo rm -rf "$TARGET_DIR"
    git clone "$REPO_URL" "$TARGET_DIR"
fi
cd "$TARGET_DIR"

########################################
# Function to convert filename to display name
# (removes "_setup.sh", replaces underscores with spaces, capitalizes each word)
########################################
to_title() {
    local base="${1%_setup.sh}"
    local spaced
    spaced=$(echo "$base" | tr '_' ' ')
    echo "$spaced" | sed -r 's/(^| )(.)/\1\u\2/g'
}

########################################
# Build checklist from files ending with _setup.sh
########################################
declare -A SCRIPT_MAPPING
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
    dialog --msgbox "No setup scripts found. Exiting." 6 50
    exit 1
fi

IFS=$'\n' sorted_display_names=($(sort <<<"${display_names[*]}"))
unset IFS

# Build main checklist items (default state "on")
checklist_items=()
declare -A OPTION_TO_NAME
option_counter=1
for name in "${sorted_display_names[@]}"; do
    checklist_items+=("$option_counter" "$name" "on")
    OPTION_TO_NAME["$option_counter"]="$name"
    ((option_counter++))
done

# Append advanced toggle for enabling advanced options (key ADV_ENABLE, label "Enable Advanced Options", default off)
advanced_toggle="ADV_ENABLE"
advanced_label="Enable Advanced Options"
checklist_items+=("$advanced_toggle" "$advanced_label" "off")

########################################
# Display main checklist dialog
########################################
main_result=$(dialog --clear --backtitle "EASY Checklist" \
  --title "E.A.S.Y. - Effortless Automated Self-hosting for You" \
  --checklist "Select the setup scripts you want to run (they will execute from top to bottom):" \
  20 80 10 "${checklist_items[@]}" 3>&1 1>&2 2>&3)

if [ -z "$main_result" ]; then
    dialog --msgbox "No options selected. Exiting." 6 50
    exit 0
fi

ADV_MODE=0
selected_numeric=()
IFS=' ' read -r -a main_opts <<< "$main_result"
for opt in "${main_opts[@]}"; do
    if [ "$opt" == "$advanced_toggle" ]; then
        ADV_MODE=1
    else
        selected_numeric+=("$opt")
    fi
done
IFS=$'\n' sorted_options=($(sort -n <<<"${selected_numeric[*]}"))
unset IFS

########################################
# If Advanced Mode is enabled, show advanced options dialog;
# if cancelled, re-display main menu.
########################################
while [ "$ADV_MODE" -eq 1 ]; do
    adv_result=$(dialog --clear --backtitle "Advanced Options" \
      --title "Advanced Options" \
      --checklist "Select Advanced Options:" 8 60 1 \
      "SHOW_OUTPUT" "Show Output" off 3>&1 1>&2 2>&3)
    ret=$?
    if [ $ret -ne 0 ] || [ -z "$adv_result" ]; then
        # If cancelled, re-display the main checklist
        main_result=$(dialog --clear --backtitle "EASY Checklist" \
          --title "E.A.S.Y. - Effortless Automated Self-hosting for You" \
          --checklist "Select the setup scripts you want to run (they will execute from top to bottom):" \
          20 80 10 "${checklist_items[@]}" 3>&1 1>&2 2>&3)
        if [ -z "$main_result" ]; then
            dialog --msgbox "No options selected. Exiting." 6 50
            exit 0
        fi
        ADV_MODE=0
        selected_numeric=()
        IFS=' ' read -r -a main_opts <<< "$main_result"
        for opt in "${main_opts[@]}"; do
            if [ "$opt" == "$advanced_toggle" ]; then
                ADV_MODE=1
            else
                selected_numeric+=("$opt")
            fi
        done
        IFS=$'\n' sorted_options=($(sort -n <<<"${selected_numeric[*]}"))
        unset IFS
        if [ "$ADV_MODE" -ne 1 ]; then
            break
        fi
    else
        if [[ "$adv_result" == *"SHOW_OUTPUT"* ]]; then
            SHOW_OUTPUT=1
        else
            SHOW_OUTPUT=0
        fi
        break
    fi
done

# Save constant copies for final reporting.
readonly FINAL_SORTED_OPTIONS=("${sorted_options[@]}")
declare -A FINAL_OPTION_TO_NAME
for key in "${!OPTION_TO_NAME[@]}"; do
    FINAL_OPTION_TO_NAME["$key"]="${OPTION_TO_NAME[$key]}"
done

########################################
# Global associative array to hold subscript results
########################################
declare -A REPORT

########################################
# Function to fully clear the terminal (including scrollback)
########################################
clear_screen() {
    clear && printf '\033[3J'
}

########################################
# Function to run a subscript:
# Clears the terminal before running.
# If SHOW_OUTPUT is enabled, outputs are shown; otherwise, hidden.
# Exit status is captured and stored in REPORT.
########################################
run_script_live() {
    local script_file="$1"
    local display_name
    display_name=$(to_title "$script_file")
    clear_screen
    echo "Running $display_name..."
    echo "----------------------------------------"
    local status=0
    if [ "$SHOW_OUTPUT" -eq 1 ]; then
        stdbuf -oL ./"$script_file"
        status=$?
    else
        stdbuf -oL ./"$script_file" &>/dev/null
        status=$?
        echo "(Output hidden)"
    fi
    echo "----------------------------------------"
    echo "$display_name completed."
    if [ "$status" -eq 0 ]; then
         REPORT["$display_name"]="on"
    else
         REPORT["$display_name"]="off"
         echo "Error: $display_name exited with status $status"
    fi
    echo "Press Enter to continue..."
    read -r
    clear_screen
}

########################################
# Run each selected subscript sequentially
########################################
for opt in "${sorted_options[@]}"; do
    display_name="${OPTION_TO_NAME[$opt]}"
    script_file="${SCRIPT_MAPPING[$display_name]}"
    run_script_live "$script_file"
done

########################################
# Build report items for final TUI report
########################################
report_items=()
for opt in "${FINAL_SORTED_OPTIONS[@]}"; do
    display_name="${FINAL_OPTION_TO_NAME[$opt]}"
    status=${REPORT["$display_name"]:-"on"}
    report_items+=("$display_name" "$display_name" "$status")
done

########################################
# Display final report using dialog checklist (read-only report)
########################################
dialog --checklist "Installation Report: (Checked = Success)" 16 80 ${#report_items[@]} "${report_items[@]}"

clear_screen
dialog --msgbox "All selected setup scripts have been executed." 6 50
clear_screen
