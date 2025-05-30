#!/bin/bash

# Linux/uninstall.sh

# --- Source helper functions ---
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
HELPER_FUNCTIONS_PATH="${SCRIPT_DIR}/helper_functions.sh"

if [ -f "${HELPER_FUNCTIONS_PATH}" ]; then
    . "${HELPER_FUNCTIONS_PATH}"
else
    echo "$(date +"%Y-%m-%d %H:%M:%S") [FATAL] helper_functions.sh not found at ${HELPER_FUNCTIONS_PATH}. Cannot proceed with logging." | tee -a "/tmp/miholess_bootstrap_fatal.log"
    exit 1
fi

# --- Default Installation Directory (match install.sh default) ---
DEFAULT_INSTALL_DIR="/opt/miholess"

log_message "Starting Miholess uninstallation..."

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    log_message "This script must be run with root privileges (or using sudo). Exiting." "ERROR"
    exit 1
fi

# Load configuration to determine actual install dir if it exists
CONFIG_FILE_PATH="${DEFAULT_INSTALL_DIR}/config.json"
if [ -f "$CONFIG_FILE_PATH" ]; then
    load_config "$CONFIG_FILE_PATH"
else
    log_message "Configuration file not found at ${CONFIG_FILE_PATH}. Using default install directory for cleanup." "WARN"
    MIHOLESS_INSTALL_DIR_NATIVE="$DEFAULT_INSTALL_DIR"
fi


# 1. Stop and disable systemd service and timers
log_message "Stopping and disabling systemd services and timers..."

SERVICES=("miholess.service" "miholess-core-updater.service" "miholess-config-updater.service")
TIMERS=("miholess-core-updater.timer" "miholess-config-updater.timer")

for timer in "${TIMERS[@]}"; do
    if systemctl is-enabled "$timer" &> /dev/null; then
        sudo systemctl stop "$timer" > /dev/null 2>&1
        sudo systemctl disable "$timer" > /dev/null 2>&1
        log_message "Timer '${timer}' stopped and disabled."
    else
        log_message "Timer '${timer}' not found or not enabled." "INFO"
    fi
done

for service in "${SERVICES[@]}"; do
    if systemctl is-enabled "$service" &> /dev/null; then
        sudo systemctl stop "$service" > /dev/null 2>&1
        sudo systemctl disable "$service" > /dev/null 2>&1
        log_message "Service '${service}' stopped and disabled."
    elif systemctl is-active "$service" &> /dev/null; then # If active but not enabled (e.g., from manual start)
        sudo systemctl stop "$service" > /dev/null 2>&1
        log_message "Service '${service}' stopped."
    else
        log_message "Service '${service}' not found or not active." "INFO"
    fi
done

sudo systemctl daemon-reload # Reload daemon after changes

# 2. Remove systemd unit files
log_message "Removing systemd unit files..."
SYSTEMD_DIR="/etc/systemd/system"
for unit_file in "${SERVICES[@]}" "${TIMERS[@]}"; do
    if [ -f "${SYSTEMD_DIR}/${unit_file}" ]; then
        sudo rm "${SYSTEMD_DIR}/${unit_file}" || log_message "Failed to remove ${SYSTEMD_DIR}/${unit_file}" "WARN"
        log_message "Removed ${SYSTEMD_DIR}/${unit_file}."
    fi
done
sudo systemctl daemon-reload # Reload again after removing files

# 3. Delete installation directory
log_message "Deleting installation directory: ${MIHOLESS_INSTALL_DIR_NATIVE}"
if [ -d "$MIHOLESS_INSTALL_DIR_NATIVE" ]; then
    sudo rm -rf "$MIHOLESS_INSTALL_DIR_NATIVE" || { log_message "Failed to remove directory: ${MIHOLESS_INSTALL_DIR_NATIVE}. Manual removal may be required." "ERROR"; exit 1; }
    log_message "Installation directory removed successfully."
else
    log_message "Installation directory '${MIHOLESS_INSTALL_DIR_NATIVE}' not found." "INFO"
fi

log_message "Miholess uninstallation completed."
