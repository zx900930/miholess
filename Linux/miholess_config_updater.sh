#!/bin/bash

# Linux/miholess_config_updater.sh

# --- Source helper functions ---
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
HELPER_FUNCTIONS_PATH="${SCRIPT_DIR}/helper_functions.sh"

if [ -f "${HELPER_FUNCTIONS_PATH}" ]; then
    . "${HELPER_FUNCTIONS_PATH}"
else
    echo "$(date +"%Y-%m-%d %H:%M:%S") [FATAL] helper_functions.sh not found at ${HELPER_FUNCTIONS_PATH}. Cannot proceed with logging." | tee -a "/tmp/miholess_bootstrap_fatal.log"
    exit 1
fi

# Load configuration
CONFIG_FILE_PATH="${MIHOLESS_INSTALL_DIR_NATIVE}/config.json" # Use helper var if possible, otherwise default
if [ -z "$MIHOLESS_INSTALL_DIR_NATIVE" ] || [ ! -f "$CONFIG_FILE_PATH" ]; then
    # If MIHOLESS_INSTALL_DIR_NATIVE is not set (e.g., script run standalone), derive from current script path
    MIHOLESS_INSTALL_DIR_NATIVE=$(dirname "$(readlink -f "$0")")
    CONFIG_FILE_PATH="${MIHOLESS_INSTALL_DIR_NATIVE}/config.json"
    if [ ! -f "$CONFIG_FILE_PATH" ]; then
        log_message "Configuration file not found at ${CONFIG_FILE_PATH}. Exiting." "ERROR"
        exit 1
    fi
fi
load_config "$CONFIG_FILE_PATH" || { log_message "Failed to load configuration. Exiting." "ERROR"; exit 1; }

log_message "Config Updater: Starting configuration update check." "INFO"

CONFIG_UPDATED=false

# Call helper function to update the main Mihomo config from the remote URL
update_mihomo_main_config "$MIHOLESS_REMOTE_CONFIG_URL" "$MIHOLESS_LOCAL_CONFIG_PATH_NATIVE"
if [ $? -eq 0 ]; then # update_mihomo_main_config returns 0 on change, 1 on no change/error
    log_message "Config Updater: Configuration updated."
    CONFIG_UPDATED=true
else
    log_message "Config Updater: No configuration changes detected or an error occurred."
fi

# After config update, restart the service if config was changed
if [ "$CONFIG_UPDATED" = "true" ]; then
    if restart_miholess_service; then
        log_message "Config Updater: Service restarted after config update."
    else
        log_message "Config Updater: Failed to restart service after config update. Please check manually." "ERROR"
    fi
fi

log_message "Config Updater: Configuration update check finished."
