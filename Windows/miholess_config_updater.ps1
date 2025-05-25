# Windows/miholess_config_updater.ps1
# This script is called by the scheduled task to update remote configurations.

# Source helper functions first for logging
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configFilePath = Join-Path $scriptDir "config.json" # native path
$helperFunctionsPath = Join-Path $scriptDir "helper_functions.ps1" # native path

if (Test-Path $helperFunctionsPath) { # Test-Path uses native path
    . $helperFunctionsPath
} else {
    # Fallback temporary logger if helper_functions.ps1 is missing
    $fallbackLogPath = "C:\ProgramData\miholess\bootstrap_updater_uninstall_fatal.log" # native path
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [FATAL] (Updater/Uninstall) helper_functions.ps1 not found at ${helperFunctionsPath}. Cannot log properly. Exiting." | Out-File -FilePath $fallbackLogPath -Append -Encoding UTF8
    } catch {}
    exit 1 # Critical failure
}
# From this point, Write-Log is available.

Write-Log "Config Updater: Starting configuration update check." "INFO"

# Load configuration using helper function
$config = Get-MiholessConfig -ConfigFilePath $configFilePath # Get-MiholessConfig expects native path

if ($null -eq $config) {
    Write-Log "Config Updater: Failed to load configuration. Exiting." "ERROR"
    exit 1
}

# Ensure LocalConfigPath uses system native backslashes for file operation when passed to helper
$localConfigPathNative = $config.local_config_path.Replace('/', '\')
$miholessInstallationDirNative = $config.installation_dir.Replace('/', '\') # Needed for miholess.ps1 path

$configUpdated = $false # Flag to track if config was updated

# Call the helper function to update the main Mihomo config from the remote URL
if (Update-MihomoMainConfig `
    -RemoteConfigUrl $config.remote_config_url `
    -LocalConfigPath $localConfigPathNative) { # LocalConfigPath is native

    Write-Log "Config Updater: Configuration updated."
    $configUpdated = $true
} else {
    Write-Log "Config Updater: No configuration changes detected."
}

# After config update, always re-run miholess.ps1 to refresh config and PID file if necessary
# and then restart the service.
if ($configUpdated) {
    Write-Log "Config Updater: Config was updated. Running miholess.ps1 for config/PID refresh and then restarting service." "INFO"
    $miholessSetupScriptPath = Join-Path $miholessInstallationDirNative "miholess.ps1"
    try {
        # Execute miholess.ps1 to ensure config/data are correct and PID is updated
        # This script runs config update logic and updates PID file, then exits.
        & "powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$miholessSetupScriptPath" | Out-Null
        Write-Log "Config Updater: miholess.ps1 executed for setup refresh."
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Config Updater: Failed to execute miholess.ps1 for setup refresh: $errorMessage." "ERROR"
    }

    if (Restart-MiholessService) {
        Write-Log "Config Updater: Service restarted after config update."
    } else {
        Write-Log "Config Updater: Failed to restart service after config update. Please check manually." "ERROR"
    }
}

Write-Log "Config Updater: Configuration update check finished."
