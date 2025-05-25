# Windows/miholess.ps1
# This script is responsible for setting up Mihomo's configuration and ensuring data directories.
# It is designed to be called by install.ps1 (once, at install) and miholess_config_updater.ps1 (periodically).
# It does NOT launch mihomo.exe or monitor it.

# Determine the actual installation directory for proper log path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configFilePath = Join-Path $scriptDir "config.json" # native path
$helperFunctionsPath = Join-Path $scriptDir "helper_functions.ps1" # native path

# --- CRITICAL: Source helper_functions.ps1 immediately ---
if (Test-Path $helperFunctionsPath) { # Test-Path uses native path
    . $helperFunctionsPath
} else {
    $fallbackLogPath = "C:\ProgramData\miholess\bootstrap_miholess_fatal.log" # native path
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [FATAL] (Miholess-Setup) helper_functions.ps1 not found at ${helperFunctionsPath}. Cannot operate. Exiting." | Out-File -FilePath $fallbackLogPath -Append -Encoding UTF8
    } catch {}
    exit 1 # Critical failure
}
# From this point, Write-Log is available.

Write-Log "Miholess.ps1 (Config/Data Setup): Script started. Loading configuration from ${configFilePath}." "INFO"
$config = Get-MiholessConfig -ConfigFilePath $configFilePath # Get-MiholessConfig expects native path

if ($null -eq $config) {
    Write-Log "Miholess.ps1 (Config/Data Setup): Failed to load configuration. Exiting." "ERROR"
    exit 1
}
# At this point, $script:config is set, and Write-Log will use its log_file or installation_dir.

# Convert paths from config (which are forward slashes) to native system backslashes for file operations
$miholessInstallationDirNative = $config.installation_dir.Replace('/', '\')
$mihomoExePath = (Join-Path $miholessInstallationDirNative "mihomo.exe")
$mihomoMainConfigPath = (Join-Path $config.local_config_path.Replace('/', '\') "config.yaml")
$mihomoDataDir = $config.local_config_path.Replace('/', '\')
# Note: $logFilePath and $pidFilePath are no longer managed/used directly by this script in the same way,
# as NSSM handles Mihomo's process and its logging directly.
# However, $pidFilePath is still useful for updater scripts to know which Mihomo PID to signal.
$pidFilePath = (Join-Path $miholessInstallationDirNative "mihomo.pid")


# Ensure the Mihomo main config file exists
Write-Log "Miholess.ps1 (Config/Data Setup): Checking for main config file at ${mihomoMainConfigPath}." "INFO"
# Ensure local config path exists before attempting to update config or download data files
if (-not (Test-Path $mihomoDataDir)) { # Test-Path uses native path
    Write-Log "Miholess.ps1 (Config/Data Setup): Creating local config/data directory: ${mihomoDataDir}" "INFO"
    try {
        New-Item -ItemType Directory -Path $mihomoDataDir -Force -ErrorAction Stop | Out-Null # New-Item uses native path
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Miholess.ps1 (Config/Data Setup): Failed to create local config directory ${mihomoDataDir}: $errorMessage. Cannot proceed. Exiting." "ERROR"
        exit 1
    }
}

# Update the main config from remote URL (if configured)
Write-Log "Miholess.ps1 (Config/Data Setup): Calling Update-MihomoMainConfig to fetch/update config.yaml." "INFO"
if (-not (Update-MihomoMainConfig -RemoteConfigUrl $config.remote_config_url -LocalConfigPath $mihomoDataDir)) {
    Write-Log "Miholess.ps1 (Config/Data Setup): Failed to create or update Mihomo configuration (config.yaml). Please check your remote config URL or create config.yaml manually in ${mihomoDataDir}." "ERROR"
    # Do not exit 1 here, allow to proceed so service might still attempt to start with what's available
} else {
    Write-Log "Miholess.ps1 (Config/Data Setup): Mihomo config.yaml updated successfully." "INFO"
}

# Ensure geodata files are in the data directory
Write-Log "Miholess.ps1 (Config/Data Setup): Calling Download-MihomoDataFiles to ensure geodata is present." "INFO"
if (-not (Download-MihomoDataFiles -DestinationDir $mihomoDataDir -GeoIpUrl $config.geoip_url -GeoSiteUrl $config.geosite_url -MmdbUrl $config.mmdb_url)) {
    Write-Log "Miholess.ps1 (Config/Data Setup): Failed to download some geodata files. Mihomo might encounter issues." "WARN"
}

# Find the PID of the *running* Mihomo process (if any) and write it to PID file.
# This is useful for updater scripts to signal restarts. NSSM manages the actual process.
Write-Log "Miholess.ps1 (Config/Data Setup): Checking for running Mihomo process to update PID file." "INFO"
try {
    # Give Mihomo a moment to start if it just did (e.g., after service restart)
    Start-Sleep -Milliseconds 200

    # Look for mihomo.exe running from the correct installation directory
    $mihomoProcess = Get-Process -Name "mihomo" -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $mihomoExePath } | Select-Object -First 1

    if ($mihomoProcess) {
        $mihomoPid = $mihomoProcess.Id
        Set-Content -Path $pidFilePath -Value $mihomoPid # Set-Content uses native path
        Write-Log "Miholess.ps1 (Config/Data Setup): Updated PID file (${pidFilePath}) with running Mihomo PID: ${mihomoPid}." "INFO"
    } else {
        # This is expected if Mihomo is not yet running, e.g. on first install
        Write-Log "Miholess.ps1 (Config/Data Setup): No running Mihomo process found from ${mihomoExePath}. PID file might not be updated." "WARN"
        # If no process found, delete PID file to prevent stale PID
        Remove-Item $pidFilePath -ErrorAction SilentlyContinue
    }
} catch {
    $errorMessage = $_.Exception.Message
    Write-Log "Miholess.ps1 (Config/Data Setup): Error updating PID file: $errorMessage." "ERROR"
}

Write-Log "Miholess.ps1 (Config/Data Setup): Script finished. Exiting gracefully." "INFO"
exit 0 # Always exit 0, indicating successful configuration/data setup
