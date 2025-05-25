# Windows/miholess_config_updater.ps1
# This script is called by the scheduled task to update remote configurations.

# Source helper functions first for logging
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$helperFunctionsPath = Join-Path $scriptDir "helper_functions.ps1"

if (Test-Path $helperFunctionsPath) {
    . $helperFunctionsPath
} else {
    # Fallback temporary logger if helper_functions.ps1 is missing
    # This log path should NOT be dependent on $config.installation_dir as config might not be loaded yet
    $fallbackLogPath = "C:\ProgramData\miholess\bootstrap_updater_uninstall_fatal.log"
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [FATAL] (Updater/Uninstall) helper_functions.ps1 not found at $helperFunctionsPath. Cannot log properly. Exiting." | Out-File -FilePath $fallbackLogPath -Append -Encoding UTF8
    } catch {}
    exit 1 # Critical failure
}

# --- Sourcing helper functions ---
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $PSScriptRoot "helper_functions.ps1")

$configFilePath = Join-Path $PSScriptRoot "config.json"
$config = Get-MiholessConfig -ConfigFilePath $configFilePath

if ($null -eq $config) {
    Write-Log "Config Updater: Failed to load configuration. Exiting." "ERROR"
    exit 1
}

Write-Log "Config Updater: Starting configuration update check..."

# Call the helper function to update the main Mihomo config from the remote URL
if (Update-MihomoMainConfig `
    -RemoteConfigUrl $config.remote_config_url `
    -LocalConfigPath $config.local_config_path) {

    Write-Log "Config Updater: Configuration updated. Restarting service..."
    if (Restart-MiholessService) {
        Write-Log "Config Updater: Service restarted after config update."
    } else {
        Write-Log "Config Updater: Failed to restart service after config update. Please check manually." "ERROR"
    }
} else {
    Write-Log "Config Updater: No service restart needed."
}

Write-Log "Config Updater: Configuration update check finished."
