# Windows/miholess.ps1
# This script is responsible for starting Mihomo and managing its configuration.
# It is typically called by miholess_service_wrapper.ps1

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
$miholessInstallationDirLocal = $config.installation_dir.Replace('/', '\')
$mihomoExePath = (Join-Path $miholessInstallationDirLocal "mihomo.exe")
$mihomoMainConfigPath = (Join-Path $config.local_config_path.Replace('/', '\') "config.yaml")
$mihomoDataDir = $config.local_config_path.Replace('/', '\')
$logFilePath = $config.log_file.Replace('/', '\') # This is Mihomo's own log file
$pidFilePath = (Join-Path $miholessInstallationDirLocal "mihomo.pid")

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

# Start Mihomo
Write-Log "Miholess.ps1: Starting Mihomo process..." "INFO"
Write-Log "Miholess.ps1: Mihomo executable: ${mihomoExePath}" "DEBUG"
Write-Log "Miholess.ps1: Mihomo main config: ${mihomoMainConfigPath}" "DEBUG"
Write-Log "Miholess.ps1: Mihomo data directory: ${mihomoDataDir}" "DEBUG"
Write-Log "Miholess.ps1: Mihomo logging to: ${logFilePath}" "DEBUG"

# Create log file for Mihomo if it doesn't exist, and ensure its directory exists
$mihomoLogDir = Split-Path $logFilePath -Parent # Native path
if (-not (Test-Path $mihomoLogDir)) { # Test-Path uses native path
    Write-Log "Miholess.ps1: Creating Mihomo log directory: ${mihomoLogDir}" "INFO"
    try {
        New-Item -Path $mihomoLogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null # New-Item uses native path
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Miholess.ps1: Failed to create Mihomo log directory ${mihomoLogDir}: $errorMessage. Mihomo logging might fail." "WARN"
    }
}
if (-not (Test-Path $logFilePath)) { # Test-Path uses native path
    Write-Log "Miholess.ps1: Creating Mihomo log file: ${logFilePath}" "INFO"
    New-Item -Path $logFilePath -ItemType File -Force | Out-Null # New-Item uses native path
}

try {
    # Arguments to Start-Process should use native paths for command line
    # WorkingDirectory needs native backslashes
    $process = Start-Process -FilePath $mihomoExePath `
        -ArgumentList "-f `"$mihomoMainConfigPath`" -d `"$mihomoDataDir`"" `
        -WorkingDirectory $miholessInstallationDirLocal `
        -RedirectStandardOutput $logFilePath `
        -RedirectStandardError $logFilePath `
        -PassThru `
        -NoNewWindow `
        -ErrorAction Stop # Ensure errors from Start-Process are caught
    
    $pid = $process.Id
    Set-Content -Path $pidFilePath -Value $pid # Set-Content uses native path
    Write-Log "Miholess.ps1: Mihomo process started successfully with PID: ${pid}. Script exiting gracefully to allow service wrapper to monitor." "INFO"

    exit 0

} catch {
    $errorMessage = $_.Exception.Message
    Write-Log "Miholess.ps1: Failed to start Mihomo: $errorMessage. Exiting." "ERROR"
    exit 1
}
