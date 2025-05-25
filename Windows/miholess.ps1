# Windows/miholess.ps1
# This script is responsible for starting Mihomo and managing its configuration.
# It is typically called by miholess_service_wrapper.ps1

# Determine the actual installation directory for proper log path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configFilePath = Join-Path $scriptDir "config.json"
$helperFunctionsPath = Join-Path $scriptDir "helper_functions.ps1"

# --- CRITICAL: Source helper_functions.ps1 immediately ---
if (Test-Path $helperFunctionsPath) {
    . $helperFunctionsPath
} else {
    $fallbackLogPath = "C:\ProgramData\miholess\bootstrap_miholess_fatal.log"
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [FATAL] (Miholess) helper_functions.ps1 not found at $helperFunctionsPath. Cannot operate. Exiting." | Out-File -FilePath $fallbackLogPath -Append -Encoding UTF8
    } catch {}
    exit 1 # Critical failure
}
# From this point, Write-Log is available.

Write-Log "Miholess.ps1: Script started. Loading configuration from $configFilePath." "INFO"
$config = Get-MiholessConfig -ConfigFilePath $configFilePath

if ($null -eq $config) {
    Write-Log "Miholess.ps1: Failed to load configuration. Exiting." "ERROR"
    exit 1
}
# At this point, $script:config is set, and Write-Log will use its log_file or installation_dir.

$mihomoExePath = Join-Path $config.installation_dir "mihomo.exe"
$mihomoMainConfigPath = Join-Path $config.local_config_path "config.yaml" # Mihomo will use this config
$mihomoDataDir = $config.local_config_path # Mihomo will use this as its data directory
$logFilePath = $config.log_file # This is Mihomo's own log file, not the service log.
$pidFilePath = $config.pid_file

Write-Log "Miholess.ps1: Checking for mihomo.exe at $mihomoExePath." "INFO"
if (-not (Test-Path $mihomoExePath)) {
    Write-Log "Miholess.ps1: mihomo.exe not found at $mihomoExePath. Please check installation. Exiting." "ERROR"
    exit 1
} else {
    Write-Log "Miholess.ps1: mihomo.exe found." "INFO"
}

# Ensure the Mihomo main config file exists, if not, attempt to update it once
Write-Log "Miholess.ps1: Checking for main config file at $mihomoMainConfigPath." "INFO"
if (-not (Test-Path $mihomoMainConfigPath)) {
    Write-Log "Miholess.ps1: Mihomo main config file not found. Attempting initial update from remote..." "WARN"
    # Ensure local config path exists before attempting to download into it
    if (-not (Test-Path $config.local_config_path)) {
        Write-Log "Miholess.ps1: Creating local config directory: $($config.local_config_path)" "INFO"
        try {
            New-Item -ItemType Directory -Path $config.local_config_path -ErrorAction Stop | Out-Null
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Miholess.ps1: Failed to create local config directory $($config.local_config_path): $errorMessage. Cannot proceed. Exiting." "ERROR"
            exit 1
        }
    }

    if (-not (Update-MihomoMainConfig -RemoteConfigUrl $config.remote_config_url -LocalConfigPath $config.local_config_path)) {
        Write-Log "Miholess.ps1: Failed to create initial Mihomo configuration. Please check your remote config URL and local config path settings. Exiting." "ERROR"
        exit 1
    }
} else {
    Write-Log "Miholess.ps1: Main config file found." "INFO"
}

# Start Mihomo
Write-Log "Miholess.ps1: Starting Mihomo process..." "INFO"
Write-Log "Miholess.ps1: Mihomo executable: $mihomoExePath" "DEBUG"
Write-Log "Miholess.ps1: Mihomo main config: $mihomoMainConfigPath" "DEBUG"
Write-Log "Miholess.ps1: Mihomo data directory: $mihomoDataDir" "DEBUG"
Write-Log "Miholess.ps1: Mihomo logging to: $logFilePath" "DEBUG"

# Create log file for Mihomo if it doesn't exist, and ensure its directory exists
$mihomoLogDir = Split-Path $logFilePath -Parent
if (-not (Test-Path $mihomoLogDir)) {
    Write-Log "Miholess.ps1: Creating Mihomo log directory: $mihomoLogDir" "INFO"
    try {
        New-Item -Path $mihomoLogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Miholess.ps1: Failed to create Mihomo log directory $mihomoLogDir: $errorMessage. Mihomo logging might fail." "WARN"
    }
}
if (-not (Test-Path $logFilePath)) {
    Write-Log "Miholess.ps1: Creating Mihomo log file: $logFilePath" "INFO"
    New-Item -Path $logFilePath -ItemType File -Force | Out-Null
}

try {
    # Start Mihomo as a background process, redirecting output to log file
    # and storing the PID for later management.
    $process = Start-Process -FilePath $mihomoExePath `
        -ArgumentList "-f `"$mihomoMainConfigPath`" -d `"$mihomoDataDir`"" `
        -WorkingDirectory $config.installation_dir ` # Mihomo.exe should be run from its own dir
        -RedirectStandardOutput $logFilePath `
        -RedirectStandardError $logFilePath `
        -PassThru `
        -NoNewWindow `
        -ErrorAction Stop # Ensure errors from Start-Process are caught
    
    $pid = $process.Id
    Set-Content -Path $pidFilePath -Value $pid
    Write-Log "Miholess.ps1: Mihomo process started successfully with PID: $pid. Script exiting gracefully to allow service wrapper to monitor." "INFO"

    # This script's job is done; the service wrapper will monitor the process.
    exit 0

} catch {
    $errorMessage = $_.Exception.Message
    Write-Log "Miholess.ps1: Failed to start Mihomo: $errorMessage. Exiting." "ERROR"
    exit 1
}
