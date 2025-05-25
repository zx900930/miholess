# Windows/miholess.ps1
# This script is responsible for setting up Mihomo's configuration and launching it.
# It is meant to be run directly by NSSM as a Windows service.

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
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [FATAL] (Miholess) helper_functions.ps1 not found at ${helperFunctionsPath}. Cannot operate. Exiting." | Out-File -FilePath $fallbackLogPath -Append -Encoding UTF8
    } catch {}
    exit 1 # Critical failure
}
# From this point, Write-Log is available.

Write-Log "Miholess.ps1: Script started. Loading configuration from ${configFilePath}." "INFO"
$config = Get-MiholessConfig -ConfigFilePath $configFilePath # Get-MiholessConfig expects native path

if ($null -eq $config) {
    Write-Log "Miholess.ps1: Failed to load configuration. Exiting." "ERROR"
    exit 1
}
# At this point, $script:config is set, and Write-Log will use its log_file or installation_dir.

# Convert paths from config (which are forward slashes) to native system backslashes for file operations
$miholessInstallationDirNative = $config.installation_dir.Replace('/', '\')
$mihomoExePath = (Join-Path $miholessInstallationDirNative "mihomo.exe")
$mihomoMainConfigPath = (Join-Path $config.local_config_path.Replace('/', '\') "config.yaml")
$mihomoDataDir = $config.local_config_path.Replace('/', '\')
$logFilePath = $config.log_file.Replace('/', '\') # This is Mihomo's own log file, managed by NSSM redirection
$pidFilePath = (Join-Path $miholessInstallationDirNative "mihomo.pid") # PID file still needed for updater scripts

Write-Log "Miholess.ps1: Checking for mihomo.exe at ${mihomoExePath}." "INFO"
if (-not (Test-Path $mihomoExePath)) { # Test-Path uses native path
    Write-Log "Miholess.ps1: mihomo.exe not found at ${mihomoExePath}. Please check installation. Exiting." "ERROR"
    exit 1
} else {
    Write-Log "Miholess.ps1: mihomo.exe found." "INFO"
}

# Ensure the Mihomo main config file exists, if not, attempt to update it once
Write-Log "Miholess.ps1: Checking for main config file at ${mihomoMainConfigPath}." "INFO"
if (-not (Test-Path $mihomoMainConfigPath)) { # Test-Path uses native path
    Write-Log "Miholess.ps1: Mihomo main config file not found. Attempting initial update from remote..." "WARN"
    # Ensure local config path exists before attempting to download into it
    if (-not (Test-Path $mihomoDataDir)) { # Test-Path uses native path
        Write-Log "Miholess.ps1: Creating local config directory: ${mihomoDataDir}" "INFO"
        try {
            New-Item -ItemType Directory -Path $mihomoDataDir -Force -ErrorAction Stop | Out-Null # New-Item uses native path
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Miholess.ps1: Failed to create local config directory ${mihomoDataDir}: $errorMessage. Cannot proceed. Exiting." "ERROR"
            exit 1
        }
    }

    # Pass local config path to Update-MihomoMainConfig with native backslashes, as it expects it
    if (-not (Update-MihomoMainConfig -RemoteConfigUrl $config.remote_config_url -LocalConfigPath $mihomoDataDir)) {
        Write-Log "Miholess.ps1: Failed to create initial Mihomo configuration. Please check your remote config URL and local config path settings. Exiting." "ERROR"
        exit 1
    }
} else {
    Write-Log "Miholess.ps1: Main config file found." "INFO"
}

# NSSM will handle stdout/stderr redirection and process monitoring/restarts.
# This script just needs to launch mihomo.exe and exit.

Write-Log "Miholess.ps1: Launching Mihomo process for NSSM to monitor..." "INFO"
Write-Log "Miholess.ps1: Mihomo executable: ${mihomoExePath}" "DEBUG"
Write-Log "Miholess.ps1: Mihomo main config: ${mihomoMainConfigPath}" "DEBUG"
Write-Log "Miholess.ps1: Mihomo data directory: ${mihomoDataDir}" "DEBUG"
# Note: Mihomo's logging will be redirected by NSSM to the configured AppStdout/AppStderr

try {
    # Start Mihomo as a background process. No need for RedirectStandardOutput here, NSSM handles it.
    # No need for PassThru, NoNewWindow, WindowStyle Hidden, ErrorAction.
    # NSSM starts miholess.ps1 in a hidden window, so mihomo.exe will inherit that.
    Start-Process -FilePath $mihomoExePath `
        -ArgumentList "-f `"$mihomoMainConfigPath`" -d `"$mihomoDataDir`"" `
        -WorkingDirectory $miholessInstallationDirNative 
    
    # After starting the process, find its PID and write it to the PID file.
    # This PID file is used by updater scripts to know which process to restart.
    Start-Sleep -Milliseconds 500 # Give Mihomo a moment to start
    
    $mihomoProcess = Get-Process -Name "mihomo" -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $mihomoExePath } | Select-Object -First 1

    if ($mihomoProcess) {
        $mihomoPid = $mihomoProcess.Id
        Set-Content -Path $pidFilePath -Value $mihomoPid
        Write-Log "Miholess.ps1: Mihomo process launched successfully with PID: ${mihomoPid}. Script exiting gracefully." "INFO"
        exit 0 # Indicate success to NSSM
    } else {
        Write-Log "Miholess.ps1: Mihomo process launched but could not find its PID. Mihomo might have failed to start. Check system logs for errors." "ERROR"
        exit 1 # Indicate failure to NSSM
    }

} catch {
    $errorMessage = $_.Exception.Message
    Write-Log "Miholess.ps1: Failed to launch Mihomo: $errorMessage. Exiting." "ERROR"
    exit 1
}
