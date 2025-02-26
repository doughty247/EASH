#!/usr/bin/env bash
set -euo pipefail

# ANSI Colors and formatting
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
RED=$(tput setaf 1)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# Function to print the EASY header in ASCII art
print_header() {
  clear
  echo "${MAGENTA}${BOLD}"
  echo "    _____    _    ______   __
  echo "   | ____|  / \  / ___\ \ / /
  echo "   |  _|   / _ \ \___ \\ V / 
  echo "   | |___ / ___ \ ___) || |  
  echo "   |_____/_/   \_\____/ |_|   "
  echo "   Effortless Automated Self-hosting for You"
  echo "${RESET}"
  echo
}

# Function to display the menu
show_menu() {
  print_header
  echo "${GREEN}1) Immich Setup${RESET}"
  echo "   ${YELLOW}- Installs and configures Immich via Docker Compose on Fedora.${RESET}"
  echo
  echo "${GREEN}2) Auto Updates Setup${RESET}"
  echo "   ${YELLOW}- Configures Docker Watchtower and automatic system updates.${RESET}"
  echo
  echo "${GREEN}3) Exit${RESET}"
  echo "============================================"
}

# Main loop for the menu
while true; do
  show_menu
  echo -n "Select an option [1-3]: "
  read -r choice
  case "$choice" in
    1)
      echo
      echo "${BOLD}Immich Setup Selected${RESET}"
      echo "This script installs and configures Immich on Fedora using Docker Compose."
      echo
      read -rp "Proceed with Immich Setup? (Y/n): " confirm
      if [[ "$confirm" =~ ^[Yy] ]]; then
          if [[ -x "./immich_setup.sh" ]]; then
              echo "${GREEN}Running Immich Setup...${RESET}"
              ./immich_setup.sh
          else
              echo "${RED}Error: immich_setup.sh not found or not executable.${RESET}"
          fi
      else
          echo "${RED}Cancelled Immich Setup.${RESET}"
      fi
      read -rp "Press Enter to return to the menu..."
      ;;
    2)
      echo
      echo "${BOLD}Auto Updates Setup Selected${RESET}"
      echo "This script sets up Docker Watchtower and configures automatic system updates on Fedora."
      echo
      read -rp "Proceed with Auto Updates Setup? (Y/n): " confirm
      if [[ "$confirm" =~ ^[Yy] ]]; then
          if [[ -x "./auto_updates_setup.sh" ]]; then
              echo "${GREEN}Running Auto Updates Setup...${RESET}"
              ./auto_updates_setup.sh
          else
              echo "${RED}Error: auto_updates_setup.sh not found or not executable.${RESET}"
          fi
      else
          echo "${RED}Cancelled Auto Updates Setup.${RESET}"
      fi
      read -rp "Press Enter to return to the menu..."
      ;;
    3)
      echo "${BLUE}Exiting. Have a great day!${RESET}"
      exit 0
      ;;
    *)
      echo "${RED}Invalid option. Please try again.${RESET}"
      sleep 1
      ;;
  esac
done
