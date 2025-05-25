# Windows/install.ps1

# --- Default Configuration Values (for interactive prompts) ---
$Default_InstallDir = "C:\ProgramData\miholess"
$Default_CoreMirror = "https://github.com/MetaCubeX/mihomo/releases/download/"
$Default_GeoIpUrl = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
$Default_GeoSiteUrl = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
$Default_MmdbUrl = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
$Default_RemoteConfigUrl = ""
$Default_LocalConfigPath = "%USERPROFILE%\\miholess_local_configs"
$Default_MihomoPort = "7890"

# --- Define a basic Write-Log function temporarily for initial steps ---
# This ensures logging works before helper_functions.ps1 is sourced
function Write-Log-Temp {
    Param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$Timestamp][$Level] $Message" | Out-Host
}

Write-Log-Temp "Starting Miholess interactive installation..."

# Check for Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log-Temp "This script must be run with Administrator privileges. Please restart PowerShell as Administrator." "ERROR"
    exit 1
}

Write-Host "`n--- Miholess Configuration ---" -ForegroundColor Yellow
Write-Host "Please provide values for the installation. Press Enter to use the default." -ForegroundColor Cyan

# 1. Get Installation Directory
$InstallDir = Read-Host "Enter installation directory (Default: $Default_InstallDir)"
if ([string]::IsNullOrEmpty($InstallDir)) { $InstallDir = $Default_InstallDir }
Write-Log-Temp "Installation Directory: $InstallDir"

# Ensure the installation directory exists before attempting to download helper functions into it
if (-not (Test-Path -Path $InstallDir)) {
    Write-Log-Temp "Creating installation directory: $InstallDir"
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
} else {
    # If it exists, we still allow to proceed to download helper functions
    Write-Log-Temp "Installation directory already exists. Proceeding..." "WARN"
}

# --- Download helper_functions.ps1 and source it ---
$helperFunctionsUrl = "https://raw.githubusercontent.com/zx900930/miholess/main/Windows/helper_functions.ps1"
$helperFunctionsPath = Join-Path $InstallDir "helper_functions.ps1"
Write-Log-Temp "Downloading helper_functions.ps1 to $helperFunctionsPath..."
try {
    # Ensure TLS 1.2 is enabled for the download
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    (New-Object System.Net.WebClient).DownloadFile($helperFunctionsUrl, $helperFunctionsPath)
    . $helperFunctionsPath # Source the downloaded helper functions
    Write-Log "helper_functions.ps1 downloaded and sourced successfully."
} catch {
    Write-Log-Temp "Failed to download or source helper_functions.ps1: $($_.Exception.Message)" "ERROR"
    exit 1
}

# From this point onwards, use the Write-Log function from helper_functions.ps1
# All other functions from helper_functions.ps1 are also now available.


# --- Continue with Interactive Input using the proper Write-Log ---
# 2. Get Mihomo Core Mirror
$CoreMirror = Read-Host "Enter Mihomo core download mirror URL (Default: $Default_CoreMirror)"
if ([string]::IsNullOrEmpty($CoreMirror)) { $CoreMirror = $Default_CoreMirror }
Write-Log "Mihomo Core Mirror: $CoreMirror"

# 3. Get GeoIP URL
$GeoIpUrl = Read-Host "Enter GeoIP.dat download URL (Default: $Default_GeoIpUrl)"
if ([string]::IsNullOrEmpty($GeoIpUrl)) { $GeoIpUrl = $Default_GeoIpUrl }
Write-Log "GeoIP URL: $GeoIpUrl"

# 4. Get GeoSite URL
$GeoSiteUrl = Read-Host "Enter GeoSite.dat download URL (Default: $Default_GeoSiteUrl)"
if ([string]::IsNullOrEmpty($GeoSiteUrl)) { $GeoSiteUrl = $Default_GeoSiteUrl }
Write-Log "GeoSite URL: $GeoSiteUrl"

# 5. Get MMDB URL
$MmdbUrl = Read-Host "Enter Country.mmdb download URL (Default: $Default_MmdbUrl)"
if ([string]::IsNullOrEmpty($MmdbUrl)) { $MmdbUrl = $Default_MmdbUrl }
Write-Log "MMDB URL: $MmdbUrl"

# 6. Get Remote Config URL
$RemoteConfigUrl = Read-Host "Enter remote configuration URL (Leave empty to use local config.yaml. Default: <empty>)"
if ([string]::IsNullOrEmpty($RemoteConfigUrl)) { $RemoteConfigUrl = $Default_RemoteConfigUrl }
Write-Log "Remote Config URL: $($RemoteConfigUrl -replace '^$', '<empty>')"

# 7. Get Local Config Path
$LocalConfigPath = Read-Host "Enter local configuration folder path (e.g., %USERPROFILE%\my_configs. Default: $Default_LocalConfigPath)"
if ([string]::IsNullOrEmpty($LocalConfigPath)) { $LocalConfigPath = $Default_LocalConfigPath }
Write-Log "Local Config Path: $LocalConfigPath"

# 8. Get Mihomo Port
$MihomoPort = Read-Host "Enter Mihomo listen port (Default: $Default_MihomoPort)"
if ([string]::IsNullOrEmpty($MihomoPort)) { $MihomoPort = $Default_MihomoPort }
Write-Log "Mihomo Port: $MihomoPort"

# 9. Force Re-installation
$ForceInput = Read-Host "Force re-installation if Miholess already exists? (Y/N, Default: N)"
$Force = ($ForceInput -eq 'Y' -or $ForceInput -eq 'y')
Write-Log "Force Re-installation: $Force"

Write-Host "`n--- Installation Summary ---" -ForegroundColor Yellow
Write-Host "Installation Directory: $InstallDir"
Write-Host "Mihomo Core Mirror: $CoreMirror"
Write-Host "GeoIP URL: $GeoIpUrl"
Write-Host "GeoSite URL: $GeoSiteUrl"
Write-Host "MMDB URL: $MmdbUrl"
Write-Host "Remote Config URL: $($RemoteConfigUrl -replace '^$', '<empty>') (Will be downloaded to $LocalConfigPath\config.yaml)"
Write-Host "Local Config Path: $LocalConfigPath (Mihomo data directory)"
Write-Host "Mihomo Port: $MihomoPort"
Write-Host "Force Re-installation: $Force"
Write-Host "`nPress Enter to proceed with installation, or Ctrl+C to cancel." -ForegroundColor Green
Pause | Out-Null # Wait for user to press enter

# --- Populate final configuration hashtable ---
$ConfigToSave = @{
    installation_dir = $InstallDir
    mihomo_core_mirror = $CoreMirror
    geoip_url = $GeoIpUrl
    geosite_url = $GeoSiteUrl
    mmdb_url = $MmdbUrl
    remote_config_url = $RemoteConfigUrl
    local_config_path = $LocalConfigPath
    log_file = (Join-Path $InstallDir "mihomo.log")
    pid_file = (Join-Path $InstallDir "mihomo.pid")
    mihomo_port = $MihomoPort
}

$MiholessInstallDir = $InstallDir # Used globally within the script (for consistency)
$MiholessServiceAccount = "NT AUTHORITY\System" # Remains constant

# 1. (Re-check) Create installation directory - already done above, but good to have safety net
if (-not (Test-Path -Path $MiholessInstallDir)) {
    Write-Log "Creating installation directory: $MiholessInstallDir (Safety check)"
    New-Item -ItemType Directory -Path $MiholessInstallDir | Out-Null
} else {
    if ($Force) {
        Write-Log "Installation directory already exists. Forcing re-installation (confirmed)."
    } else {
        Write-Log "Installation directory already exists and not forcing re-installation. Exiting." "ERROR"
        exit 1
    }
}

# 2. Save configuration to JSON file
$ConfigFilePath = Join-Path $MiholessInstallDir "config.json"
Write-Log "Saving configuration to $ConfigFilePath"
$ConfigToSave | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigFilePath -Encoding UTF8

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

# 5. Copy remaining scripts to installation directory (by downloading from GitHub)
Write-Log "Downloading remaining Miholess scripts to $MiholessInstallDir..."
# helper_functions.ps1 is already downloaded and sourced
$scriptsToDownload = @(
    "miholess_core_updater.ps1",
    "miholess_config_updater.ps1",
    "miholess_service_wrapper.ps1",
    "miholess.ps1",
    "uninstall.ps1" # Add uninstall script to ensure it's always in the install dir
)
foreach ($script in $scriptsToDownload) {
    $sourceUrl = "https://raw.githubusercontent.com/zx900930/miholess/main/Windows/$script"
    $destPath = Join-Path $MiholessInstallDir $script
    Write-Log "Downloading '$script' from '$sourceUrl'..."
    try {
        (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destPath)
        Write-Log "Downloaded '$script'."
    } catch {
        Write-Log "Warning: Failed to download '$script' from '$sourceUrl': $($_.Exception.Message). Skipping." "WARN"
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
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
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

# Function to safely register a scheduled task (local to install.ps1 as it's not in helper_functions yet)
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
# Run every hour starting at midnight, duration 1 day (meaning it will run for 24 hours, then then repeat daily)
$triggerConfig = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1) -At "00:00" 
Register-MiholessScheduledTask -TaskName $taskNameConfig -Description "Updates Mihomo remote and local configurations." `
    -ScriptPath $scriptConfigPath -Triggers $triggerConfig -Settings $commonSettings

Write-Log "Scheduled tasks created successfully."

Write-Log "Miholess installation completed successfully!"
Write-Log "You can check service status with: Get-Service MiholessService"
Write-Log "And scheduled tasks with: Get-ScheduledTask -TaskName Miholess_*"
Write-Log "To configure, edit: $ConfigFilePath"
