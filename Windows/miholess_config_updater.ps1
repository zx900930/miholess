# Windows/miholess_config_updater.ps1
# This script is called by the scheduled task to update remote configurations.

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
