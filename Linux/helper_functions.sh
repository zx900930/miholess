#!/bin/bash

# Linux/helper_functions.sh

# --- Logging Functions ---
log_message() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local level=${2:-INFO} # Default to INFO if level not provided
    echo "[${timestamp}][${level}] ${1}" | tee -a "${MIHOLESS_INSTALL_DIR_NATIVE}/miholess_service.log"
}

# --- Configuration Management ---
# Global variables for paths, populated by installer.
# Use these as defaults or read from config.json.
MIHOLESS_INSTALL_DIR_JSON="\$HOME/.miholess" # Default for Linux, using $HOME for user
MIHOLESS_INSTALL_DIR_NATIVE="" # Will be expanded and converted
MIHOLESS_LOCAL_CONFIG_PATH_JSON="\$HOME/.miholess_local_configs" # Default for Linux, using $HOME for user
MIHOLESS_LOCAL_CONFIG_PATH_NATIVE="" # Will be expanded and converted

get_config_value() {
    local config_file="${1}"
    local key="${2}"
    if [ ! -f "${config_file}" ]; then
        log_message "Configuration file not found: ${config_file}" "ERROR"
        return 1
    fi
    # Use -r to output raw strings, --arg to pass keys safely
    value=$(jq -r --arg key "$key" '.[$key]' "${config_file}")
    if [ "$value" == "null" ]; then
        # jq returns "null" if key not found or value is JSON null
        # We assume empty string for missing non-string values
        echo ""
        return 0
    fi
    echo "$value"
}

load_config() {
    local config_file="${1}"
    if [ ! -f "${config_file}" ]; then
        log_message "Configuration file not found: ${config_file}" "ERROR"
        return 1
    fi

    # Read config values into script variables (prefix with MIHOLESS_)
    # Ensure they are expanded and converted to native paths immediately after loading.
    MIHOLESS_INSTALL_DIR_JSON=$(get_config_value "${config_file}" "installation_dir")
    MIHOLESS_INSTALL_DIR_NATIVE=$(eval echo "${MIHOLESS_INSTALL_DIR_JSON}" | sed 's/\//\//g') # Convert to native (forward slashes on Linux)

    MIHOLESS_CORE_MIRROR=$(get_config_value "${config_file}" "mihomo_core_mirror")
    MIHOLESS_GEOIP_URL=$(get_config_value "${config_file}" "geoip_url")
    MIHOLESS_GEOSITE_URL=$(get_config_value "${config_file}" "geosite_url")
    MIHOLESS_MMDB_URL=$(get_config_value "${config_file}" "mmdb_url")
    MIHOLESS_REMOTE_CONFIG_URL=$(get_config_value "${config_file}" "remote_config_url")

    MIHOLESS_LOCAL_CONFIG_PATH_JSON=$(get_config_value "${config_file}" "local_config_path")
    MIHOLESS_LOCAL_CONFIG_PATH_NATIVE=$(eval echo "${MIHOLESS_LOCAL_CONFIG_PATH_JSON}" | sed 's/\//\//g') # Convert to native (forward slashes on Linux)

    MIHOLESS_LOG_FILE=$(get_config_value "${config_file}" "log_file")
    MIHOLESS_PID_FILE=$(get_config_value "${config_file}" "pid_file")
    MIHOLESS_MIHOMO_PORT=$(get_config_value "${config_file}" "mihomo_port")

    # Ensure native paths are populated, even if config.json is empty or default
    if [ -z "$MIHOLESS_INSTALL_DIR_NATIVE" ]; then
        MIHOLESS_INSTALL_DIR_NATIVE=$(eval echo "${MIHOLESS_INSTALL_DIR_JSON}" | sed 's/\//\//g')
    fi
    if [ -z "$MIHOLESS_LOCAL_CONFIG_PATH_NATIVE" ]; then
        MIHOLESS_LOCAL_CONFIG_PATH_NATIVE=$(eval echo "${MIHOLESS_LOCAL_CONFIG_PATH_JSON}" | sed 's/\//\//g')
    fi

    log_message "Configuration loaded from ${config_file}." "DEBUG"
    return 0
}


# --- Mihomo Core Download & Update Logic ---
get_latest_mihomo_download_url() {
    local os_type="${1:-linux}"
    local arch="${2:-amd64}"
    local exclude_go_versions="${3:-true}"
    local base_mirror="${4:-https://github.com/MetaCubeX/mihomo/releases/download/}"

    log_message "Fetching latest Mihomo release info from GitHub API..."
    local api_url="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"

    release_info=$(curl -s "$api_url")
    if [ $? -ne 0 ]; then
        log_message "Error fetching release info from GitHub API. Check network or API rate limits." "ERROR"
        return 1
    fi

    tag_name=$(echo "$release_info" | jq -r '.tag_name')
    if [ -z "$tag_name" ] || [ "$tag_name" == "null" ]; then
        log_message "Could not find tag_name in the latest release info." "ERROR"
        return 1
    fi

    assets=$(echo "$release_info" | jq -c '.assets[]')
    if [ -z "$assets" ]; then
        log_message "No assets found for the latest release." "ERROR"
        return 1
    fi
    log_message "DEBUG: Found $(echo "$assets" | wc -l) assets."

    local os_arch_pattern="mihomo-${os_type}-${arch}"
    local candidate_urls=()

    while IFS= read -r asset; do
        asset_name=$(echo "$asset" | jq -r '.name')
        download_url=$(echo "$asset" | jq -r '.browser_download_url')

        if [ -z "$asset_name" ] || [ "$asset_name" == "null" ] || \
           [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
            continue
        fi

        if [[ "$asset_name" != *"$os_arch_pattern"* ]]; then
            continue
        fi

        if [ "$exclude_go_versions" = "true" ] && [[ "$asset_name" =~ -go[0-9]+ ]]; then
            continue
        fi

        log_message "DEBUG: Candidate - Asset: ${asset_name}, URL: ${download_url}"

        if [[ "$asset_name" == *"compatible"* ]]; then
            candidate_urls=("$download_url" "${candidate_urls[@]}") # Prepend
        else
            candidate_urls+=("$download_url") # Append
        fi
    done <<< "$assets"

    if [ ${#candidate_urls[@]} -eq 0 ]; then
        log_message "No suitable Mihomo binary found for ${os_type}-${arch} (excluding Go versions: ${exclude_go_versions})." "ERROR"
        return 1
    fi
    log_message "DEBUG: Found ${#candidate_urls[@]} candidate URLs. First candidate: ${candidate_urls[0]}"

    local final_url="${candidate_urls[0]}"

    if [ "$base_mirror" != "https://github.com/MetaCubeX/mihomo/releases/download/" ] && \
       [[ "$final_url" == *"github.com/MetaCubeX/mihomo/releases/download/"* ]]; then
        local relative_path=$(echo "$final_url" | sed "s|https://github.com/MetaCubeX/mihomo/releases/download/||")
        final_url="${base_mirror}${relative_path}"
        log_message "Using custom mirror: ${base_mirror}"
    fi
    
    log_message "DEBUG: Final URL before return: ${final_url}"
    echo "$final_url"
    return 0
}

download_and_extract_mihomo() {
    local download_url="${1}"
    local destination_dir="${2}" # Native path

    if [ -z "$download_url" ]; then
        log_message "Download URL is empty. Skipping Mihomo download." "ERROR"
        return 1
    fi
    if [ -z "$destination_dir" ]; then
        log_message "Destination directory is empty. Skipping Mihomo download." "ERROR"
        return 1
    fi

    log_message "Downloading Mihomo from ${download_url}"
    local temp_file=$(mktemp "/tmp/mihomo_temp_XXXXXX")
    local success=0

    curl -L -o "$temp_file" "$download_url"
    if [ $? -ne 0 ]; then
        log_message "Failed to download Mihomo from ${download_url}. Check URL or network." "ERROR"
        rm -f "$temp_file"
        return 1
    fi

    log_message "Extracting Mihomo to ${destination_dir}"

    local target_exe_name="mihomo" # Linux executable typically has no .exe
    local target_exe_path="${destination_dir}/${target_exe_name}"

    # Stop existing mihomo process if running from target path
    if pgrep -f "${target_exe_path}"; then
        log_message "Existing mihomo process detected. Attempting to stop..." "WARN"
        sudo pkill -f "${target_exe_path}"
        sleep 1
        if pgrep -f "${target_exe_path}"; then
            log_message "Could not stop existing mihomo process. It might be in use." "WARN"
            # Attempt forceful kill
            sudo pkill -9 -f "${target_exe_path}"
            sleep 1
        fi
    fi

    # Remove existing mihomo executable before extraction
    if [ -f "$target_exe_path" ]; then
        rm -f "$target_exe_path"
    fi

    local extracted_name=""
    local archive_type=""

    if [[ "$download_url" == *".zip"* ]]; then
        archive_type="zip"
        unzip -o -d "$destination_dir" "$temp_file"
    elif [[ "$download_url" == *".tar.gz"* ]] || [[ "$download_url" == *".gz"* ]]; then
        archive_type="tar.gz"
        tar -xzf "$temp_file" -C "$destination_dir"
    else
        log_message "Unsupported archive type for ${download_url}. Assuming single executable." "WARN"
        cp "$temp_file" "$target_exe_path"
        success=1 # Assume direct copy for simplicity if type unknown
    fi

    if [ "$success" -eq 0 ]; then # If extraction was attempted
        # Find the actual Mihomo executable after extraction (it might be in a subdir or named differently)
        # Look for files matching 'mihomo*' inside the destination_dir
        local found_exe=$(find "$destination_dir" -type f -name "mihomo*" -perm /u+x -print -quit) # find executable files
        
        if [ -z "$found_exe" ]; then
            log_message "Could not find any executable (mihomo*) after extraction in ${destination_dir}. Checking for any files named mihomo." "ERROR"
            found_exe=$(find "$destination_dir" -type f -name "mihomo" -print -quit) # Check for files named 'mihomo' even if not executable
        fi

        if [ -n "$found_exe" ]; then
            if [ "$found_exe" != "$target_exe_path" ]; then
                log_message "Renaming and moving '$(basename "$found_exe")' to '${target_exe_path}'."
                mv "$found_exe" "$target_exe_path"
                # Clean up empty parent directories if it was moved from a subfolder
                local parent_dir=$(dirname "$found_exe")
                if [ "$parent_dir" != "$destination_dir" ] && [ -z "$(ls -A "$parent_dir")" ]; then
                    rmdir "$parent_dir" 2>/dev/null || true # rmdir only if empty, suppress errors
                fi
            else
                log_message "Mihomo executable found as ${target_exe_name} in ${destination_dir}."
            fi
            chmod +x "$target_exe_path" # Ensure it's executable
            success=1
        else
            log_message "Could not find mihomo executable after extraction/copy. Expected: ${target_exe_path}" "ERROR"
        fi
    fi

    rm -f "$temp_file" # Clean up temp archive
    if [ "$success" -eq 1 ]; then
        log_message "Mihomo downloaded and extracted successfully."
        return 0
    else
        log_message "Failed to extract Mihomo." "ERROR"
        return 1
    fi
}

download_mihomo_data_files() {
    local destination_dir="${1}" # Native path
    local geoip_url="${2}"
    local geosite_url="${3}"
    local mmdb_url="${4}"

    if [ -z "$destination_dir" ]; then
        log_message "Destination directory for data files is empty or null. Cannot download data files." "ERROR"
        return 1
    fi

    log_message "Downloading data files to ${destination_dir}..."
    mkdir -p "$destination_dir" # Ensure directory exists

    local data_files_urls=(
        "geoip.dat;$geoip_url"
        "geosite.dat;$geosite_url"
        "country.mmdb;$mmdb_url"
    )
    local all_success=0 # 0 for success, 1 for failure

    for entry in "${data_files_urls[@]}"; do
        IFS=';' read -r filename url <<< "$entry"
        local destination="${destination_dir}/${filename}"

        if [ -z "$url" ]; then
            log_message "URL for ${filename} is empty. Skipping download." "WARN"
            continue
        fi

        log_message "Downloading ${filename} from ${url}"
        curl -L -o "$destination" "$url"
        if [ $? -ne 0 ]; then
            log_message "Failed to download ${filename}: Check URL or network." "WARN"
            all_success=1
        else
            log_message "${filename} downloaded successfully."
        fi
    done
    return "$all_success"
}

# --- Service Management ---
systemctl_cmd() {
    local command="${1}" # enable, disable, start, stop, restart, status
    local service_name="${2}" # miholess.service
    local result=""
    log_message "Attempting 'systemctl ${command} ${service_name}'..."
    if [ "$command" = "status" ]; then
        systemctl "$command" "$service_name" > /dev/null 2>&1
    else
        sudo systemctl "$command" "$service_name" > /dev/null 2>&1
    fi
    if [ $? -eq 0 ]; then
        log_message "Service '${service_name}' ${command}ed successfully."
        return 0
    else
        result=$(systemctl status "$service_name" 2>&1)
        log_message "Failed to ${command} service '${service_name}': ${result}" "ERROR"
        return 1
    fi
}

restart_miholess_service() {
    local service_name="miholess.service"
    log_message "Attempting to restart Miholess service..."
    if systemctl_cmd "is-active" "$service_name"; then
        if systemctl_cmd "restart" "$service_name"; then
            log_message "Miholess service restarted successfully."
            return 0
        else
            log_message "Failed to restart Miholess service." "ERROR"
            return 1
        fi
    else
        log_message "Miholess service '${service_name}' not found or not active. Attempting to start..." "WARN"
        if systemctl_cmd "start" "$service_name"; then
            log_message "Miholess service started successfully."
            return 0
        else
            log_message "Failed to start Miholess service." "ERROR"
            return 1
        fi
    fi
}

# --- Config Update Logic ---
update_mihomo_main_config() {
    local remote_config_url="${1}"
    local local_config_path="${2}" # Native path

    log_message "Updating Mihomo main configuration from remote URL..."

    if [ -z "$remote_config_url" ]; then
        log_message "No remote configuration URL provided. Skipping config update." "INFO"
        return 1 # Indicate no change/skip
    fi

    mkdir -p "$local_config_path" # Ensure directory exists

    local target_config_file="${local_config_path}/config.yaml"
    log_message "Downloading remote config from: ${remote_config_url} to ${target_config_file}"

    local new_config_content=$(curl -sL "$remote_config_url")
    if [ $? -ne 0 ]; then
        log_message "Failed to download remote config from ${remote_config_url}. Check URL or network." "ERROR"
        return 1
    fi

    if [ -z "$new_config_content" ]; then
        log_message "Downloaded remote config is empty. Not updating existing config." "WARN"
        return 1 # Indicate no change
    fi

    local existing_config_content=""
    if [ -f "$target_config_file" ]; then
        existing_config_content=$(cat "$target_config_file")
    fi

    if [ "$new_config_content" != "$existing_config_content" ]; then
        log_message "Configuration content changed. Saving new config..."
        echo "$new_config_content" > "$target_config_file"
        if [ $? -eq 0 ]; then
            log_message "Main Mihomo config saved to ${target_config_file}"
            return 0 # Indicate change was made
        else
            log_message "Failed to save final Mihomo config." "ERROR"
            return 1
        fi
    else
        log_message "Configuration content is identical. No change needed."
        return 1 # Indicate no change
    fi
}
