# Windows/install.ps1

# --- Sourcing helper functions ---
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $PSScriptRoot "helper_functions.ps1")

# --- Parameters for script execution (with literal defaults) ---
# These parameters now define their own default values directly.
Param(
    [string]$InstallDir = "C:\ProgramData\miholess",
    [string]$CoreMirror = "https://github.com/MetaCubeX/mihomo/releases/download/",
    [string]$GeoIpUrl = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat",
    [string]$GeoSiteUrl = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat",
    [string]$MmdbUrl = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb",
    [string]$RemoteConfigUrl = "",
    [string]$LocalConfigPath = "%USERPROFILE%\\miholess_local_configs",
    [string]$MihomoPort = "7890",
    [switch]$Force
)

# --- Configuration Variables (Populated from parameters) ---
# These variables now get their values from the parameters defined above.
# If no parameters are passed, they will use the literal defaults from the Param block.
$MiholessInstallDir = $InstallDir
$MiholessServiceAccount = "NT AUTHORITY\System" # This remains a constant

$DefaultConfig = @{
    installation_dir = $InstallDir
    mihomo_core_mirror = $CoreMirror
    geoip_url = $GeoIpUrl
    geosite_url = $GeoSiteUrl
    mmdb_url = $MmdbUrl
    remote_config_url = $RemoteConfigUrl
    local_config_path = $LocalConfigPath
    log_file = (Join-Path $InstallDir "mihomo.log") # Use $InstallDir here directly
    pid_file = (Join-Path $InstallDir "mihomo.pid")   # Use $InstallDir here directly
    mihomo_port = $MihomoPort
}

# --- Main Installation Logic ---
Write-Log "Starting Miholess installation..."

# Check for Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script must be run with Administrator privileges. Please restart PowerShell as Administrator." "ERROR"
    exit 1
}

# 1. Create installation directory
if (-not (Test-Path -Path $MiholessInstallDir)) {
    Write-Log "Creating installation directory: $MiholessInstallDir"
    New-Item -ItemType Directory -Path $MiholessInstallDir | Out-Null
} else {
    if ($Force) {
        Write-Log "Installation directory already exists. Forcing re-installation."
        # No recursive removal here, individual components will be replaced/recreated
    } else {
        Write-Log "Installation directory already exists. To proceed, please use -Force or run uninstall.ps1 first." "ERROR"
        exit 1
    }
}

# 2. Save configuration to JSON file
$ConfigFilePath = Join-Path $MiholessInstallDir "config.json"
Write-Log "Saving configuration to $ConfigFilePath"
$DefaultConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigFilePath -Encoding UTF8

# 3. Download and Extract Mihomo Core
$mihomoDownloadUrl = Get-LatestMihomoDownloadUrl -OsType "windows" -Arch "amd64" -BaseMirror $CoreMirror
if ($null -eq $mihomoDownloadUrl) {
    Write-Log "Failed to get Mihomo download URL. Installation aborted." "ERROR"
    exit 1
}

if (-not (Download-AndExtractMihomo -DownloadUrl $mihomoDownloadUrl -DestinationDir $MiholessInstallDir)) {
    Write-Log "Failed to download and extract Mihomo. Installation aborted." "ERROR"
    exit 1
}

# 4. Download GeoIP, GeoSite, MMDB files
if (-not (Download-MihomoDataFiles -InstallationDir $MiholessInstallDir -GeoIpUrl $GeoIpUrl -GeoSiteUrl $GeoSiteUrl -MmdbUrl $MmdbUrl)) {
    Write-Log "Some data files failed to download. Check logs for details." "WARN"
}

# 5. Copy scripts to installation directory
Write-Log "Copying Miholess scripts to $MiholessInstallDir..."
$scriptsToCopy = @(
    "miholess_core_updater.ps1",
    "miholess_config_updater.ps1",
    "miholess_service_wrapper.ps1",
    "miholess.ps1",
    "helper_functions.ps1"
)
foreach ($script in $scriptsToCopy) {
    $sourcePath = Join-Path $PSScriptRoot $script
    $destPath = Join-Path $MiholessInstallDir $script
    if (Test-Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $destPath -Force
        Write-Log "Copied '$script'."
    } else {
        Write-Log "Warning: Script '$script' not found at '$sourcePath'. Skipping copy." "WARN"
    }
}


# 6. Create Windows Service
$serviceName = "MiholessService"
$displayName = "Miholess Core Service"
$description = "Manages Mihomo core and configurations, ensures autostart."
$serviceBinaryPath = "powershell.exe"
$serviceArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$MiholessInstallDir\miholess_service_wrapper.ps1`""

# Check if service exists and remove if Force is used
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    Write-Log "Service '$serviceName' already exists. Stopping and removing old service..." "WARN"
    Stop-Service -Name $serviceName -ErrorAction SilentlyContinue
    Remove-Service -Name $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2 # Give it a moment to clean up
}

Write-Log "Creating Windows Service '$serviceName'..."
try {
    New-Service -Name $serviceName -DisplayName $displayName -Description $description `
                -BinaryPathName "$serviceBinaryPath $serviceArguments" `
                -StartupType Automatic -ErrorAction Stop
    
    # Set service dependencies (e.g., depends on network being available)
    # Using sc.exe for more robust dependency setting
    $dependCmd = "sc.exe config $serviceName depend= Nsi/TcpIp"
    Write-Log "Setting service dependency: $dependCmd"
    Invoke-Expression $dependCmd | Out-Null # Redirect output to null

    Set-Service -Name $serviceName -Status Running -ErrorAction Stop # Start the service
    Write-Log "Windows Service '$serviceName' created and started successfully."
} catch {
    Write-Log "Failed to create or start Windows Service '$serviceName': $($_.Exception.Message)" "ERROR"
    exit 1
}


# 7. Create Scheduled Tasks
Write-Log "Creating scheduled tasks..."

# Function to safely register a scheduled task
function Register-MiholessScheduledTask {
    Param(
        [string]$TaskName,
        [string]$Description,
        [string]$ScriptPath,
        [ScheduledTaskTrigger[]]$Triggers,
        [ScheduledTaskSettingsSet]$Settings
    )
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Write-Log "Scheduled task '$TaskName' already exists. Removing old task..." "WARN"
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    Write-Log "Registering scheduled task '$TaskName'..."
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        Register-ScheduledTask -Action $action -Trigger $Triggers -TaskName $TaskName -Description $Description -Settings $Settings -Force
        Write-Log "Scheduled task '$TaskName' registered successfully."
    } catch {
        Write-Log "Failed to register scheduled task '$TaskName': $($_.Exception.Message)" "ERROR"
    }
}

$commonSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -StopIfGoingOnBatteries:$false -DontStopIfGoingOnBatteries -AllowStartOnDemand -Enabled -RunOnlyIfNetworkAvailable

# Task: Mihomo Core Updater
$taskNameCore = "Miholess_Core_Updater"
$scriptCorePath = Join-Path $MiholessInstallDir "miholess_core_updater.ps1"
$triggerCore = New-ScheduledTaskTrigger -Daily -At "03:00" # Run daily at 3 AM
Register-MiholessScheduledTask -TaskName $taskNameCore -Description "Updates Mihomo core to the latest non-Go version." `
    -ScriptPath $scriptCorePath -Triggers $triggerCore -Settings $commonSettings

# Task: Mihomo Config Updater
$taskNameConfig = "Miholess_Config_Updater"
$scriptConfigPath = Join-Path $MiholessInstallDir "miholess_config_updater.ps1"
# Run every hour starting at midnight, duration 1 day (meaning it will run for 24 hours, then reset)
$triggerConfig = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1) -At "00:00" 
Register-MiholessScheduledTask -TaskName $taskNameConfig -Description "Updates Mihomo remote and local configurations." `
    -ScriptPath $scriptConfigPath -Triggers $triggerConfig -Settings $commonSettings

Write-Log "Scheduled tasks created successfully."

Write-Log "Miholess installation completed successfully!"
Write-Log "You can check service status with: Get-Service MiholessService"
Write-Log "And scheduled tasks with: Get-ScheduledTask -TaskName Miholess_*"
Write-Log "To configure, edit: $ConfigFilePath"
