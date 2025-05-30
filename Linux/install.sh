#!/bin/bash

# Linux/install.sh

# --- Source helper functions ---
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
HELPER_FUNCTIONS_PATH="${SCRIPT_DIR}/helper_functions.sh"

if [ -f "${HELPER_FUNCTIONS_PATH}" ]; then
    . "${HELPER_FUNCTIONS_PATH}"
else
    # Fallback basic logging if helper_functions.sh is missing
    echo "$(date +"%Y-%m-%d %H:%M:%S") [FATAL] helper_functions.sh not found at ${HELPER_FUNCTIONS_PATH}. Cannot proceed." | tee -a "/tmp/miholess_bootstrap_fatal.log"
    exit 1
fi

# --- Default Configuration Values (for interactive prompts) ---
# Use forward slashes for all internal defaults and examples for JSON compatibility
DEFAULT_INSTALL_DIR="/opt/miholess" # Standard for system-wide software
DEFAULT_CORE_MIRROR="https://github.com/MetaCubeX/mihomo/releases/download/"
DEFAULT_GEOIP_URL="https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
DEFAULT_GEOSITE_URL="https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
DEFAULT_MMDB_URL="https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
DEFAULT_REMOTE_CONFIG_URL=""
DEFAULT_LOCAL_CONFIG_PATH="/etc/mihomo" # Centralized config location
DEFAULT_MIHOMO_PORT="7890"

# --- Main Installation Logic ---
log_message "Starting Miholess interactive installation..."

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    log_message "This script must be run with root privileges (or using sudo). Exiting." "ERROR"
    exit 1
fi

log_message "Checking for required dependencies..."
DEPENDENCIES=("curl" "jq" "tar" "gzip" "unzip")
MISSING_DEPS=()
for dep in "${DEPENDENCIES[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log_message "Missing dependencies: ${MISSING_DEPS[*]}. Attempting to install..." "WARN"
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y "${MISSING_DEPS[@]}"
    elif command -v yum &> /dev/null; then
        sudo yum install -y "${MISSING_DEPS[@]}"
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y "${MISSING_DEPS[@]}"
    else
        log_message "Cannot automatically install missing dependencies. Please install them manually: ${MISSING_DEPS[*]}." "ERROR"
        exit 1
    fi

    # Re-check after installation attempt
    for dep in "${MISSING_DEPS[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_message "Failed to install ${dep}. Exiting." "ERROR"
            exit 1
        fi
    done
fi
log_message "All dependencies found."

echo ""
echo "--- Miholess Configuration ---"
echo "Please provide values for the installation. Press Enter to use the default."

# 1. Get Installation Directory
read -p "Enter installation directory (Default: ${DEFAULT_INSTALL_DIR}): " INSTALL_DIR_INPUT
if [ -z "$INSTALL_DIR_INPUT" ]; then INSTALL_DIR_INPUT="$DEFAULT_INSTALL_DIR"; fi
MIHOLESS_INSTALL_DIR_JSON=$(eval echo "${INSTALL_DIR_INPUT}" | sed 's/\/$//') # Remove trailing slash for consistency
MIHOLESS_INSTALL_DIR_NATIVE=$(eval echo "${MIHOLESS_INSTALL_DIR_JSON}") # For Linux, JSON path == Native path

log_message "Installation Directory: ${MIHOLESS_INSTALL_DIR_NATIVE}"

# Ensure installation directory exists
mkdir -p "$MIHOLESS_INSTALL_DIR_NATIVE" || { log_message "Failed to create ${MIHOLESS_INSTALL_DIR_NATIVE}. Exiting." "ERROR"; exit 1; }

# 2. Get Mihomo Core Mirror
read -p "Enter Mihomo core download mirror URL (Default: ${DEFAULT_CORE_MIRROR}): " CORE_MIRROR
if [ -z "$CORE_MIRROR" ]; then CORE_MIRROR="$DEFAULT_CORE_MIRROR"; fi
log_message "Mihomo Core Mirror: ${CORE_MIRROR}"

# 3. Get GeoIP URL
read -p "Enter GeoIP.dat download URL (Default: ${DEFAULT_GEOIP_URL}): " GEOIP_URL
if [ -z "$GEOIP_URL" ]; then GEOIP_URL="$DEFAULT_GEOIP_URL"; fi
log_message "GeoIP URL: ${GEOIP_URL}"

# 4. Get GeoSite URL
read -p "Enter GeoSite.dat download URL (Default: ${DEFAULT_GEOSITE_URL}): " GEOSITE_URL
if [ -z "$GEOSITE_URL" ]; then GEOSITE_URL="$DEFAULT_GEOSITE_URL"; fi
log_message "GeoSite URL: ${GEOSITE_URL}"

# 5. Get MMDB URL
read -p "Enter Country.mmdb download URL (Default: ${DEFAULT_MMDB_URL}): " MMDB_URL
if [ -z "$MMDB_URL" ]; then MMDB_URL="$DEFAULT_MMDB_URL"; fi
log_message "MMDB URL: ${MMDB_URL}"

# 6. Get Remote Config URL
read -p "Enter remote configuration URL (Leave empty to use local config.yaml. Default: <empty>): " REMOTE_CONFIG_URL
if [ -z "$REMOTE_CONFIG_URL" ]; then REMOTE_CONFIG_URL="$DEFAULT_REMOTE_CONFIG_URL"; fi
log_message "Remote Config URL: ${REMOTE_CONFIG_URL:-<empty>}"

# 7. Get Local Config Path
read -p "Enter local configuration folder path (e.g., /etc/mihomo. Default: ${DEFAULT_LOCAL_CONFIG_PATH}): " LOCAL_CONFIG_PATH_INPUT
if [ -z "$LOCAL_CONFIG_PATH_INPUT" ]; then LOCAL_CONFIG_PATH_INPUT="$DEFAULT_LOCAL_CONFIG_PATH"; fi
MIHOLESS_LOCAL_CONFIG_PATH_JSON=$(eval echo "${LOCAL_CONFIG_PATH_INPUT}" | sed 's/\/$//') # Remove trailing slash
MIHOLESS_LOCAL_CONFIG_PATH_NATIVE=$(eval echo "${MIHOLESS_LOCAL_CONFIG_PATH_JSON}") # For Linux, JSON path == Native path
if [ -z "$MIHOLESS_LOCAL_CONFIG_PATH_NATIVE" ]; then
    MIHOLESS_LOCAL_CONFIG_PATH_NATIVE=$(eval echo "${DEFAULT_LOCAL_CONFIG_PATH}")
    log_message "Local Config Path was empty after expansion, set to default: ${MIHOLESS_LOCAL_CONFIG_PATH_NATIVE}" "WARN"
fi
log_message "Local Config Path: ${MIHOLESS_LOCAL_CONFIG_PATH_NATIVE}"

# 8. Get Mihomo Port
read -p "Enter Mihomo listen port (Default: ${DEFAULT_MIHOMO_PORT}): " MIHOMO_PORT
if [ -z "$MIHOMO_PORT" ]; then MIHOMO_PORT="$DEFAULT_MIHOMO_PORT"; fi
log_message "Mihomo Port: ${MIHOMO_PORT}"

# 9. Force Re-installation
read -p "Force re-installation if Miholess already exists? (Y/N, Default: N): " FORCE_INPUT
FORCE_INSTALL=false
if [[ "$FORCE_INPUT" =~ ^[Yy]$ ]]; then
    FORCE_INSTALL=true
fi
log_message "Force Re-installation: ${FORCE_INSTALL}"

echo ""
echo "--- Installation Summary ---"
echo "Installation Directory: ${MIHOLESS_INSTALL_DIR_NATIVE}"
echo "Mihomo Core Mirror: ${CORE_MIRROR}"
echo "GeoIP URL: ${GEOIP_URL}"
echo "GeoSite URL: ${GEOSITE_URL}"
echo "MMDB URL: ${MMDB_URL}"
echo "Remote Config URL: ${REMOTE_CONFIG_URL:-<empty>} (Will be downloaded to ${MIHOLESS_LOCAL_CONFIG_PATH_NATIVE}/config.yaml)"
echo "Local Config Path: ${MIHOLESS_LOCAL_CONFIG_PATH_NATIVE} (Mihomo data directory)"
echo "Mihomo Port: ${MIHOMO_PORT}"
echo "Force Re-installation: ${FORCE_INSTALL}"
echo ""
read -p "Press Enter to proceed with installation, or Ctrl+C to cancel."

# Check if existing installation should be removed
if [ -d "$MIHOLESS_INSTALL_DIR_NATIVE" ]; then
    if [ "$FORCE_INSTALL" = "true" ]; then
        log_message "Existing installation detected. Forcing re-installation. Running uninstaller first..." "WARN"
        "${SCRIPT_DIR}/uninstall.sh" || { log_message "Uninstallation of existing setup failed. Exiting." "ERROR"; exit 1; }
        log_message "Old installation cleaned up."
    else
        log_message "Existing installation detected. Not forcing re-installation. Exiting." "ERROR"
        exit 1
    fi
fi

# Recreate installation directory if needed after potential uninstall
mkdir -p "$MIHOLESS_INSTALL_DIR_NATIVE" || { log_message "Failed to create installation directory: ${MIHOLESS_INSTALL_DIR_NATIVE}. Exiting." "ERROR"; exit 1; }

# 1. Save configuration to JSON file
CONFIG_FILE_PATH="${MIHOLESS_INSTALL_DIR_NATIVE}/config.json"
log_message "Saving configuration to ${CONFIG_FILE_PATH}"
jq -n \
  --arg installdir "$MIHOLESS_INSTALL_DIR_JSON" \
  --arg coremirror "$MIHOLESS_CORE_MIRROR" \
  --arg geoipurl "$GEOIP_URL" \
  --arg geositeurl "$GEOSITE_URL" \
  --arg mmdburl "$MMDB_URL" \
  --arg remoteconfigurl "$REMOTE_CONFIG_URL" \
  --arg localconfigpath "$MIHOLESS_LOCAL_CONFIG_PATH_JSON" \
  --arg logfile "${MIHOLESS_INSTALL_DIR_JSON}/mihomo.log" \
  --arg pidfile "${MIHOLESS_INSTALL_DIR_JSON}/mihomo.pid" \
  --arg mihomoport "$MIHOMO_PORT" \
  '{
    "installation_dir": $installdir,
    "mihomo_core_mirror": $coremirror,
    "geoip_url": $geoipurl,
    "geosite_url": $geositeurl,
    "mmdb_url": $mmdburl,
    "remote_config_url": $remoteconfigurl,
    "local_config_path": $localconfigpath,
    "log_file": $logfile,
    "pid_file": $pidfile,
    "mihomo_port": $mihomoport
  }' > "$CONFIG_FILE_PATH" || { log_message "Failed to write config.json. Exiting." "ERROR"; exit 1; }

# 2. Download and Extract Mihomo Core
MIHOMO_DOWNLOAD_URL=$(get_latest_mihomo_download_url "linux" "amd64" "true" "$CORE_MIRROR") # Use $MIHOLESS_CORE_MIRROR here
if [ $? -ne 0 ]; then
    log_message "Failed to get Mihomo download URL. Installation aborted." "ERROR"
    exit 1
fi

download_and_extract_mihomo "$MIHOMO_DOWNLOAD_URL" "$MIHOLESS_INSTALL_DIR_NATIVE"
if [ $? -ne 0 ]; then
    log_message "Failed to download and extract Mihomo. Installation aborted." "ERROR"
    exit 1
fi

# 3. Download GeoIP, GeoSite, MMDB files
mkdir -p "$MIHOLESS_LOCAL_CONFIG_PATH_NATIVE" # Ensure local config path exists before downloading data files
download_mihomo_data_files "$MIHOLESS_LOCAL_CONFIG_PATH_NATIVE" "$GEOIP_URL" "$GEOSITE_URL" "$MMDB_URL"
if [ $? -ne 0 ]; then
    log_message "Some data files failed to download. Check logs for details." "WARN"
fi

# 4. Copy Miholess scripts to installation directory
log_message "Copying Miholess scripts to ${MIHOLESS_INSTALL_DIR_NATIVE}..."
cp "${SCRIPT_DIR}/helper_functions.sh" "$MIHOLESS_INSTALL_DIR_NATIVE/" || { log_message "Failed to copy helper_functions.sh. Exiting." "ERROR"; exit 1; }
chmod +x "$MIHOLESS_INSTALL_DIR_NATIVE/helper_functions.sh"
cp "${SCRIPT_DIR}/miholess_core_updater.sh" "$MIHOLESS_INSTALL_DIR_NATIVE/" || { log_message "Failed to copy miholess_core_updater.sh. Exiting." "ERROR"; exit 1; }
chmod +x "$MIHOLESS_INSTALL_DIR_NATIVE/miholess_core_updater.sh"
cp "${SCRIPT_DIR}/miholess_config_updater.sh" "$MIHOLESS_INSTALL_DIR_NATIVE/" || { log_message "Failed to copy miholess_config_updater.sh. Exiting." "ERROR"; exit 1; }
chmod +x "$MIHOLESS_INSTALL_DIR_NATIVE/miholess_config_updater.sh"
cp "${SCRIPT_DIR}/miholess.service" "/etc/systemd/system/" || { log_message "Failed to copy miholess.service. Exiting." "ERROR"; exit 1; }

# 5. Configure Mihomo service unit file
log_message "Configuring miholess.service unit file..."
# Replace placeholders in the service file
sed -i "s|ExecStart=.*|ExecStart=${MIHOLESS_INSTALL_DIR_NATIVE}/mihomo -f ${MIHOLESS_LOCAL_CONFIG_PATH_NATIVE}/config.yaml -d ${MIHOLESS_LOCAL_CONFIG_PATH_NATIVE}|g" "/etc/systemd/system/miholess.service"
sed -i "s|WorkingDirectory=.*|WorkingDirectory=${MIHOLESS_INSTALL_DIR_NATIVE}|g" "/etc/systemd/system/miholess.service"

# You might want to run as a dedicated user (e.g., 'miholess') instead of root for security.
# For simplicity, default to root for now or ensure Mihomo can read/write its dirs.
# sed -i "s|^User=.*|User=root|g" "/etc/systemd/system/miholess.service" # Ensure it runs as root or specific user

# 6. Enable and start systemd service
log_message "Enabling and starting miholess.service..."
systemctl daemon-reload || { log_message "Failed to reload systemd daemon. Exiting." "ERROR"; exit 1; }
systemctl enable miholess.service || { log_message "Failed to enable miholess.service. Exiting." "ERROR"; exit 1; }
systemctl start miholess.service || { log_message "Failed to start miholess.service. Exiting." "ERROR"; exit 1; }
log_message "Miholess service started successfully."

# 7. Create systemd timers for scheduled tasks
log_message "Creating systemd timers for updates..."

# Core Updater Timer
CORE_UPDATER_SERVICE_FILE="miholess-core-updater.service"
CORE_UPDATER_TIMER_FILE="miholess-core-updater.timer"

cat <<EOF | sudo tee "/etc/systemd/system/${CORE_UPDATER_SERVICE_FILE}" > /dev/null
[Unit]
Description=Miholess Core Updater Service
After=network-online.target

[Service]
Type=oneshot
ExecStart=${MIHOLESS_INSTALL_DIR_NATIVE}/miholess_core_updater.sh
EOF

cat <<EOF | sudo tee "/etc/systemd/system/${CORE_UPDATER_TIMER_FILE}" > /dev/null
[Unit]
Description=Run Miholess Core Updater Daily

[Timer]
OnCalendar=daily
AccuracySec=1h
Persistent=true # Run even if system was off
EOF

systemctl enable "${CORE_UPDATER_SERVICE_FILE}"
systemctl enable "${CORE_UPDATER_TIMER_FILE}"
systemctl start "${CORE_UPDATER_TIMER_FILE}"

# Config Updater Timer
CONFIG_UPDATER_SERVICE_FILE="miholess-config-updater.service"
CONFIG_UPDATER_TIMER_FILE="miholess-config-updater.timer"

cat <<EOF | sudo tee "/etc/systemd/system/${CONFIG_UPDATER_SERVICE_FILE}" > /dev/null
[Unit]
Description=Miholess Config Updater Service
After=network-online.target

[Service]
Type=oneshot
ExecStart=${MIHOLESS_INSTALL_DIR_NATIVE}/miholess_config_updater.sh
EOF

cat <<EOF | sudo tee "/etc/systemd/system/${CONFIG_UPDATER_TIMER_FILE}" > /dev/null
[Unit]
Description=Run Miholess Config Updater Hourly

[Timer]
OnCalendar=hourly
AccuracySec=15m # Run roughly every hour
Persistent=true
EOF

systemctl enable "${CONFIG_UPDATER_SERVICE_FILE}"
systemctl enable "${CONFIG_UPDATER_TIMER_FILE}"
systemctl start "${CONFIG_UPDATER_TIMER_FILE}"

systemctl daemon-reload

log_message "Scheduled tasks created successfully."

log_message "Miholess installation completed successfully!"
log_message "You can check service status with: systemctl status miholess.service"
log_message "And timers with: systemctl list-timers miholess-*"
log_message "To configure, edit: ${CONFIG_FILE_PATH}"
log_message "Mihomo main config: ${MIHOLESS_LOCAL_CONFIG_PATH_NATIVE}/config.yaml"
