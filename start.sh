#!/usr/bin/env bash
# Version: 1.1.18 Stable Release
# Last Updated: 2025-02-26
# Description: EASY - Effortless Automated Self-hosting for You
# This script checks that you're on Fedora, installs required tools,
# clones/updates the EASY repo (using sudo rm -rf to remove any old copy),
# and dynamically builds a checklist from all files in the EASY directory
# ending with "_setup.sh". Displayed names have the suffix removed,
# underscores replaced with spaces, and each word capitalized.
# All subscript items are enabled by default.
# The main checklist includes an extra toggle "Enable Advanced Options".
# If that toggle is selected, a separate dialog lets you toggle "Show Output" (default off).
# When running a selected subscript:
#   - If "Show Output" is enabled, output is printed normally.
#   - Otherwise, the subscript is run in trace mode with a progress gauge that updates
#     based on the percentage of non-comment, non-blank lines executed.
# The gauge displays a constant message ("Running <name>...") without showing command counts.
# After running all subscripts, a final report is displayed indicating success for each.
#
set -uo pipefail  # -e removed so that subscript failures do not abort the main script

# Initialize SHOW_OUTPUT variable
SHOW_OUTPUT=0

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
# Build checklist from files ending with _setup.sh
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
    dialog --msgbox "No setup scripts found. Exiting." 6 50
    exit 1
fi

IFS=$'\n' sorted_display_names=($(sort <<<"${display_names[*]}"))
unset IFS

# Build main checklist items for subscript selections (default state "on")
checklist_items=()
declare -A OPTION_TO_NAME
option_counter=1
for name in "${sorted_display_names[@]}"; do
    checklist_items+=("$option_counter" "$name" "on")
    OPTION_TO_NAME["$option_counter"]="$name"
    ((option_counter++))
done

# Append extra toggle for enabling advanced options (key: ADV_ENABLE, label: "Enable Advanced Options", default off)
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
# If Advanced Mode is enabled, display advanced options dialog;
# if cancelled, re-display the main menu.
########################################
while [ "$ADV_MODE" -eq 1 ]; do
    adv_result=$(dialog --clear --backtitle "Advanced Options" \
      --title "Advanced Options" \
      --checklist "Select Advanced Options:" 8 60 1 \
      "SHOW_OUTPUT" "Show Output" off 3>&1 1>&2 2>&3)
    ret=$?
    if [ $ret -ne 0 ] || [ -z "$adv_result" ]; then
        # Re-display main menu if advanced options dialog is cancelled
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
# Function: Fully clear terminal (including scrollback)
########################################
clear_screen() {
    clear && printf '\033[3J'
}

########################################
# Function: Run a subscript.
# Clears the terminal before running.
# If SHOW_OUTPUT is enabled, output is shown normally.
# Otherwise, the subscript is run in trace mode with a progress gauge updating based on executed lines.
# The gauge displays a constant message without command counters.
# Exit status is stored in REPORT.
########################################
run_script_live() {
    local script_file="$1"
    local display_name
    display_name=$(to_title "$script_file")
    clear_screen
    echo "Setting up $display_name..."
    echo "----------------------------------------"
    local status=0
    if [ "$SHOW_OUTPUT" -eq 1 ]; then
        stdbuf -oL ./"$script_file"
        status=$?
    else
        # Calculate total executable lines (non-blank, non-comment)
        total=$(grep -v '^\s*$' "$script_file" | grep -v '^\s*#' | wc -l)
        temp_file=$(mktemp)
        bash -x "$script_file" &> "$temp_file" &
        script_pid=$!
        # Use a single gauge instance that reads from a subshell
        (
          while kill -0 "$script_pid" 2>/dev/null; do
            current=$(grep -c '^+' "$temp_file")
            if [ "$total" -gt 0 ]; then
                percent=$(( current * 100 / total ))
            else
                percent=100
            fi
            echo "$percent"
            sleep 0.5
          done
        ) | dialog --gauge "Setting up $display_name..." 6 60 0
        wait "$script_pid"
        status=$?
        rm -f "$temp_file"
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
# Build final report items for TUI report (default to on if not set)
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
dialog --checklist "Installation Report:" 16 80 ${#report_items[@]} "${report_items[@]}"

clear_screen
dialog --msgbox "All Done!" 6 50
clear_screen
wait 1
clear
exit
