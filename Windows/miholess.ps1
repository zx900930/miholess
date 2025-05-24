# Windows/miholess.ps1
# This script is responsible for starting Mihomo and managing its configuration.
# It is typically called by miholess_service_wrapper.ps1

# --- Sourcing helper functions ---
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $PSScriptRoot "helper_functions.ps1")

$configFilePath = Join-Path $PSScriptRoot "config.json"
$config = Get-MiholessConfig -ConfigFilePath $configFilePath

if ($null -eq $config) {
    Write-Log "Failed to load configuration. Exiting miholess.ps1." "ERROR"
    exit 1
}

$mihomoExePath = Join-Path $config.installation_dir "mihomo.exe"
$mihomoMainConfigPath = Join-Path $config.local_config_path "config.yaml" # Mihomo will use this config
$mihomoDataDir = $config.local_config_path # Mihomo will use this as its data directory
$logFilePath = $config.log_file
$pidFilePath = $config.pid_file

if (-not (Test-Path $mihomoExePath)) {
    Write-Log "mihomo.exe not found at $mihomoExePath. Please run install.ps1." "ERROR"
    exit 1
}

# Ensure the Mihomo main config file exists, if not, attempt to update it once
if (-not (Test-Path $mihomoMainConfigPath)) {
    Write-Log "Mihomo main config file not found at $mihomoMainConfigPath. Attempting initial update from remote..." "WARN"
    if (-not (Update-MihomoMainConfig -RemoteConfigUrl $config.remote_config_url -LocalConfigPath $config.local_config_path)) {
        Write-Log "Failed to create initial Mihomo configuration. Please check your remote config URL and local config path settings. Exiting." "ERROR"
        exit 1
    }
}

# Start Mihomo
Write-Log "Starting Mihomo process..."
Write-Log "Mihomo executable: $mihomoExePath"
Write-Log "Mihomo main config: $mihomoMainConfigPath"
Write-Log "Mihomo data directory: $mihomoDataDir"
Write-Log "Mihomo log: $logFilePath"

# Create log file if it doesn't exist
if (-not (Test-Path $logFilePath)) {
    New-Item -Path $logFilePath -ItemType File -Force | Out-Null
}

try {
    # Start Mihomo as a background process, redirecting output to log file
    # and storing the PID for later management.
    # The mihomo_service_wrapper.ps1 will be responsible for keeping this alive.
    $mihomoProcess = Start-Process -FilePath $mihomoExePath `
        -ArgumentList "-f `"$mihomoMainConfigPath`" -d `"$mihomoDataDir`"" `
        -WorkingDirectory $config.installation_dir ` # It's better Mihomo.exe stays in installation_dir to find its own resources
        -RedirectStandardOutput $logFilePath `
        -RedirectStandardError $logFilePath `
        -PassThru `
        -NoNewWindow # Essential for service operation

    $pid = $mihomoProcess.Id
    Set-Content -Path $pidFilePath -Value $pid
    Write-Log "Mihomo process started with PID: $pid"

    # In a service context, this script usually just starts the process and exits
    # The service wrapper will monitor it.
    exit 0

} catch {
    Write-Log "Failed to start Mihomo: $($_.Exception.Message)" "ERROR"
    exit 1
}
