#!/bin/bash

# Linux/miholess_core_updater.sh

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


log_message "Core Updater: Starting Mihomo core update check." "INFO"

CURRENT_MIHOMO_EXE_PATH="${MIHOLESS_INSTALL_DIR_NATIVE}/mihomo"
CURRENT_MIHOMO_VERSION="Unknown"

# Attempt to get current Mihomo version
log_message "Core Updater: Checking current Mihomo version from ${CURRENT_MIHOMO_EXE_PATH}." "INFO"
if [ -f "$CURRENT_MIHOMO_EXE_PATH" ]; then
    # Run mihomo -v and parse output, redirecting stderr to stdout
    MIHOMO_OUTPUT=$("$CURRENT_MIHOMO_EXE_PATH" -v 2>&1)
    # Common patterns: "Version: x.y.z", "mihomo version x.y.z"
    VERSION_MATCH=$(echo "$MIHOMO_OUTPUT" | grep -oP '(Version|mihomo version)\s*\K([vV]?[0-9]+\.[0-9]+\.[0-9]+)')
    if [ -n "$VERSION_MATCH" ]; then
        CURRENT_MIHOMO_VERSION=$(echo "$VERSION_MATCH" | head -n 1) # Take first match
    else
        log_message "Core Updater: Could not determine current Mihomo version from output: ${MIHOMO_OUTPUT}" "WARN"
    fi
else
    log_message "Core Updater: Mihomo executable not found at ${CURRENT_MIHOMO_EXE_PATH}." "WARN"
fi
log_message "Core Updater: Current Mihomo version: ${CURRENT_MIHOMO_VERSION}"

LATEST_DOWNLOAD_URL=$(get_latest_mihomo_download_url "linux" "amd64" "true" "$MIHOLESS_CORE_MIRROR")
if [ $? -ne 0 ]; then
    log_message "Core Updater: Failed to get latest Mihomo download URL. Aborting update." "ERROR"
    exit 1
fi

# Extract version from URL for comparison (e.g., v1.19.9/mihomo-linux-amd64-v1.19.9.gz)
LATEST_VERSION=$(echo "$LATEST_DOWNLOAD_URL" | grep -oP 'v([0-9]+\.[0-9]+\.[0-9]+)\.(zip|gz)')
LATEST_VERSION=${LATEST_VERSION##v} # Remove 'v' prefix
LATEST_VERSION=${LATEST_VERSION%%.*} # Remove everything after first dot (e.g., .zip or .gz)

if [ -z "$LATEST_VERSION" ]; then
    log_message "Core Updater: Could not parse latest version from URL: ${LATEST_DOWNLOAD_URL}" "WARN"
    LATEST_VERSION="Unknown"
fi
log_message "Core Updater: Latest available Mihomo version: ${LATEST_VERSION}"

CORE_UPDATED=false

if [ "$CURRENT_MIHOMO_VERSION" != "Unknown" ] && [ "$LATEST_VERSION" != "Unknown" ]; then
    # Simple version comparison (e.g., 1.19.0 > 1.18.9) requires specific string manipulation or 'sort -V'
    # Use 'sort -V' for robust version comparison
    if [[ $(printf '%s\n' "$CURRENT_MIHOMO_VERSION" "$LATEST_VERSION" | sort -V | head -n 1) == "$CURRENT_MIHOMO_VERSION" ]] && \
       [[ "$CURRENT_MIHOMO_VERSION" != "$LATEST_VERSION" ]]; then
        log_message "Core Updater: New Mihomo version (${LATEST_VERSION}) is available! Current: ${CURRENT_MIHOMO_VERSION}" "INFO"
        download_and_extract_mihomo "$LATEST_DOWNLOAD_URL" "$MIHOLESS_INSTALL_DIR_NATIVE"
        if [ $? -eq 0 ]; then
            log_message "Core Updater: Mihomo core updated."
            CORE_UPDATED=true
        else
            log_message "Core Updater: Failed to download and extract new Mihomo core." "ERROR"
        fi
    else
        log_message "Core Updater: Mihomo core is already up-to-date (${CURRENT_MIHOMO_VERSION}). No update needed." "INFO"
    fi
else
    log_message "Core Updater: Cannot determine current or latest version reliably. Attempting to download latest anyway." "WARN"
    download_and_extract_mihomo "$LATEST_DOWNLOAD_URL" "$MIHOLESS_INSTALL_DIR_NATIVE"
    if [ $? -eq 0 ]; then
        log_message "Core Updater: Mihomo core updated (version comparison skipped)."
        CORE_UPDATED=true
    else
        log_message "Core Updater: Failed to download and extract new Mihomo core." "ERROR"
    fi
fi

# After core update, re-run miholess.sh to refresh config and PID file if necessary
# and then restart the service.
if [ "$CORE_UPDATED" = "true" ]; then
    log_message "Core Updater: Core was updated. Running miholess.sh for config/PID refresh and then restarting service." "INFO"
    MIHOLESS_SETUP_SCRIPT_PATH="${MIHOLESS_INSTALL_DIR_NATIVE}/miholess.sh" # This script doesn't exist yet, it's miholess.ps1 in Windows.
                                                                           # On Linux, miholess.service directly runs mihomo.
                                                                           # We just need to trigger config update here.
    
    # We call config updater directly, then restart service
    log_message "Core Updater: Triggering config update via miholess_config_updater.sh after core update."
    "${MIHOLESS_INSTALL_DIR_NATIVE}/miholess_config_updater.sh" || log_message "Core Updater: Config updater failed after core update." "WARN"

    if restart_miholess_service; then
        log_message "Core Updater: Service restarted after core update."
    else
        log_message "Core Updater: Failed to restart service after core update. Please check manually." "ERROR"
    fi
fi

log_message "Core Updater: Mihomo core update check finished."
