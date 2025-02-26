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
# Define setup scripts and their descriptions
# (Describes what each app does)
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

# If no setup scripts found, exit.
if [ "${#SCRIPT_MAP[@]}" -eq 0 ]; then
    dialog --msgbox "No setup scripts found. Exiting." 6 50
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
    dialog --msgbox "No options selected. Exiting." 6 50
    exit 0
fi

# Parse and sort the result
IFS=' ' read -r -a selected_options <<< "$result"
IFS=$'\n' sorted=($(sort -n <<<"${selected_options[*]}"))
unset IFS

########################################
# Function to run a script with live output using a FIFO
########################################
run_script_live() {
    local script_file="$1"
    # Create a FIFO (named pipe)
    fifo=$(mktemp -u)
    mkfifo "$fifo"
    # Launch dialog tailbox in background to display live output
    dialog --title "Live Output: $(basename "$script_file" .sh)" --tailbox "$fifo" 20 80 &
    tailbox_pid=$!
    # Run the script with forced line buffering, writing output to the FIFO.
    stdbuf -oL ./"$script_file" > "$fifo" 2>&1
    # When the script finishes, remove the FIFO.
    rm "$fifo"
    # Kill the tailbox if it's still running
    kill $tailbox_pid 2>/dev/null || true
}

########################################
# Run each selected setup script in order (top to bottom) with live output
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
