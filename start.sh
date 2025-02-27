#!/usr/bin/env bash
# Version: 1.1.13 Stable Release (with Advanced Options Re-run)
# Last Updated: 2025-02-26

set -uo pipefail  # -e removed so that subscript failures do not abort the main script

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
    cd "$HOME"  # Move out of the repository directory
    sudo rm -rf "$TARGET_DIR"
    git clone "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"

########################################
# Function: Convert filename to display name:
# Remove "_setup.sh", replace underscores with spaces, capitalize each word.
########################################
to_title() {
    local base="${1%_setup.sh}"
    local spaced
    spaced=$(echo "$base" | tr '_' ' ')
    echo "$spaced" | sed -r 's/(^| )(.)/\1\u\2/g'
}

########################################
# Build main checklist from files ending with _setup.sh
########################################
declare -A SCRIPT_MAPPING  # Maps display name to script filename
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

IFS=$'\n' sorted_display_names=($(sort <<<"${display_names[*]}"))
unset IFS

# Build checklist items for subscript selections (default "on")
checklist_items=()
declare -A OPTION_TO_NAME
option_counter=1
for name in "${sorted_display_names[@]}"; do
    checklist_items+=("$option_counter" "$name" "on")
    OPTION_TO_NAME["$option_counter"]="$name"
    ((option_counter++))
done

# Append advanced options toggle for enabling advanced mode (key: ADV_ENABLE, label: "Enable Advanced Options", default off)
advanced_toggle="ADV_ENABLE"
advanced_label="Enable Advanced Options"
checklist_items+=("$advanced_toggle" "$advanced_label" "off")

########################################
# Loop: Display main checklist until advanced options dialog is not cancelled.
########################################
while true; do
    main_result=$(dialog --clear --backtitle "EASY Checklist" \
      --title "E.A.S.Y. - Effortless Automated Self-hosting for You" \
      --checklist "Select the setup scripts you want to run (they will execute from top to bottom):" \
      20 80 10 "${checklist_items[@]}" 3>&1 1>&2 2>&3)
    
    if [ -z "$main_result" ]; then
        dialog --msgbox "No options selected. Exiting." 6 50
        exit 0
    fi

    # Process main_result: Numeric keys for subscript items, ADV_ENABLE for advanced mode toggle.
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

    # If Advanced Mode is enabled, display advanced options dialog.
    if [ "$ADV_MODE" -eq 1 ]; then
        adv_result=$(dialog --clear --backtitle "Advanced Options" \
          --title "Advanced Options" \
          --checklist "Select Advanced Options:" 8 60 1 \
          "SHOW_OUTPUT" "Show Output" off 3>&1 1>&2 2>&3)
        ret=$?
        if [ $ret -ne 0 ]; then
            # If canceled, re-run main menu.
            continue
        else
            if [[ "$adv_result" == *"SHOW_OUTPUT"* ]]; then
                SHOW_OUTPUT=1
            else
                SHOW_OUTPUT=0
            fi
        fi
    else
        SHOW_OUTPUT=0
    fi
    break
done

# Save constant copies for final reporting.
readonly FINAL_SORTED_OPTIONS=("${sorted_options[@]}")
declare -A FINAL_OPTION_TO_NAME
for key in "${!OPTION_TO_NAME[@]}"; do
    FINAL_OPTION_TO_NAME["$key"]="${OPTION_TO_NAME[$key]}"
done

########################################
# Global associative array to hold subscript results (on = success, off = failure)
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
# Clears terminal before running.
# If SHOW_OUTPUT is enabled, output is displayed; otherwise, hidden.
# Exit status is stored in REPORT.
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
# Build report items for final TUI report (default to on if no status recorded)
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
