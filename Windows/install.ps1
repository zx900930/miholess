# Windows/install.ps1
# This script performs the interactive installation. It is meant to be called by bootstrap_install.ps1.

# --- Default Configuration Values (for interactive prompts) ---
# Use forward slashes for all internal defaults and examples for JSON compatibility
$Default_InstallDir = "C:/ProgramData/miholess"
$Default_CoreMirror = "https://github.com/MetaCubeX/mihomo/releases/download/"
$Default_GeoIpUrl = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
$Default_GeoSiteUrl = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
$Default_MmdbUrl = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
$Default_RemoteConfigUrl = ""
$Default_LocalConfigPath = "%USERPROFILE%/miholess_local_configs" # Changed to forward slashes
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
# Ensure input/default is sanitized to forward slashes for JSON
$InstallDir = Read-Host "Enter installation directory (Default: $Default_InstallDir)"
if ([string]::IsNullOrEmpty($InstallDir)) { $InstallDir = $Default_InstallDir }
$InstallDir = ([System.Environment]::ExpandEnvironmentVariables($InstallDir)).Replace('\', '/') # Expand and standardize slashes
Write-Log-Temp "Installation Directory: $InstallDir"

# Ensure the installation directory exists before attempting to download helper functions into it
# For file system ops, use system native path
$InstallDirLocal = $InstallDir.Replace('/', '\')
if (-not (Test-Path -Path $InstallDirLocal)) {
    Write-Log-Temp "Creating installation directory: $InstallDirLocal"
    New-Item -ItemType Directory -Path $InstallDirLocal | Out-Null
} else {
    Write-Log-Temp "Installation directory already exists. Proceeding with potential re-installation." "WARN"
}

# --- Download helper_functions.ps1 and source it ---
$helperFunctionsUrl = "https://raw.githubusercontent.com/zx900930/miholess/main/Windows/helper_functions.ps1"
$helperFunctionsPath = Join-Path $InstallDirLocal "helper_functions.ps1" # Use native path for download destination
Write-Log-Temp "Downloading helper_functions.ps1 to $helperFunctionsPath..."
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    (New-Object System.Net.WebClient).DownloadFile($helperFunctionsUrl, $helperFunctionsPath)
    . $helperFunctionsPath # Source the downloaded helper functions (uses native path)
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
# Ensure input/default is sanitized to forward slashes for JSON
$LocalConfigPath = Read-Host "Enter local configuration folder path (e.g., %USERPROFILE%/my_configs. Default: $($Default_LocalConfigPath))"
if ([string]::IsNullOrEmpty($LocalConfigPath)) { $LocalConfigPath = $Default_LocalConfigPath }
$LocalConfigPath = ([System.Environment]::ExpandEnvironmentVariables($LocalConfigPath)).Replace('\', '/') # Expand and standardize slashes
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
Write-Host "Remote Config URL: $($RemoteConfigUrl -replace '^$', '<empty>') (Will be downloaded to $LocalConfigPath/config.yaml)"
Write-Host "Local Config Path: $LocalConfigPath (Mihomo data directory)"
Write-Host "Mihomo Port: $MihomoPort"
Write-Host "Force Re-installation: $Force"
Write-Host "`nPress Enter to proceed with installation, or Ctrl+C to cancel." -ForegroundColor Green
Pause | Out-Null # Wait for user to press enter

# --- Populate final configuration hashtable ---
# All paths here are already sanitized to use forward slashes for JSON safety
$ConfigToSave = @{
    installation_dir = $InstallDir
    mihomo_core_mirror = $CoreMirror
    geoip_url = $GeoIpUrl
    geosite_url = $GeoSiteUrl
    mmdb_url = $MmdbUrl
    remote_config_url = $RemoteConfigUrl
    local_config_path = $LocalConfigPath
    log_file = "${InstallDir}/mihomo.log"
    pid_file = "${InstallDir}/mihomo.pid"
    mihomo_port = $MihomoPort
}

$MiholessInstallDir = $InstallDir # For global script scope, still in forward slashes
$MiholessServiceAccount = "NT AUTHORITY\System" # Remains constant

# 1. (Re-check) Create installation directory - already done above, but good to have safety net
# Use native path for Test-Path and New-Item
if (-not (Test-Path -Path $MiholessInstallDirLocal)) {
    Write-Log "Creating installation directory: ${MiholessInstallDirLocal} (Safety check)" # Use ${} for paths in log
    New-Item -ItemType Directory -Path $MiholessInstallDirLocal | Out-Null
} else {
    if ($Force) {
        Write-Log "Installation directory already exists. Forcing re-installation (confirmed)."
    } else {
        Write-Log "Installation directory already exists and not forcing re-installation. Exiting." "ERROR"
        exit 1
    }
}

# 2. Save configuration to JSON file
$ConfigFilePath = Join-Path $MiholessInstallDirLocal "config.json" # Use native path for file system
Write-Log "Saving configuration to ${ConfigFilePath}" # Use ${} in log
$ConfigToSave | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigFilePath -Encoding UTF8 # Save with local path

# 3. Download and Extract Mihomo Core
$mihomoDownloadUrl = Get-LatestMihomoDownloadUrl -OsType "windows" -Arch "amd64" -BaseMirror $CoreMirror
if ($null -eq $mihomoDownloadUrl) {
    Write-Log "Failed to get Mihomo download URL. Installation aborted." "ERROR"
    exit 1
}

# Use native path for DestinationDir
if (-not (Download-AndExtractMihomo -DownloadUrl $mihomoDownloadUrl -DestinationDir $MiholessInstallDirLocal)) {
    Write-Log "Failed to download and extract Mihomo. Installation aborted." "ERROR"
    exit 1
}

# 4. Download GeoIP, GeoSite, MMDB files
if (-not (Download-MihomoDataFiles -InstallationDir $MiholessInstallDirLocal -GeoIpUrl $GeoIpUrl -GeoSiteUrl $GeoSiteUrl -MmdbUrl $MmdbUrl)) {
    Write-Log "Some data files failed to download. Check logs for details." "WARN"
}

# 5. Download remaining scripts to installation directory (by downloading from GitHub)
Write-Log "Downloading remaining Miholess scripts to ${MiholessInstallDirLocal}..." # Use native path in log
# helper_functions.ps1 is already downloaded and sourced
$scriptsToDownload = @(
    "miholess_core_updater.ps1",
    "miholess_config_updater.ps1",
    "miholess_service_wrapper.ps1",
    "miholess.ps1",
    "uninstall.ps1" # Ensure uninstall script is present
)
foreach ($script in $scriptsToDownload) {
    $sourceUrl = "https://raw.githubusercontent.com/zx900930/miholess/main/Windows/$script"
    # Ensure destPath uses system native backslashes for file operation
    $destPath = (Join-Path $MiholessInstallDirLocal $script)
    Write-Log "Downloading '${script}' from '${sourceUrl}' to '${destPath}'..." # Added destPath to log
    try {
        (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destPath)
        Write-Log "Downloaded '${script}'."
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Warning: Failed to download '${script}' from '${sourceUrl}': $errorMessage. Skipping." "WARN"
    }
}


# 6. Create Windows Service
$serviceName = "MiholessService"
$displayName = "Miholess Core Service"
$description = "Manages Mihomo core and configurations, ensures autostart."
# Service binary path must use native system backslashes
$serviceBinaryPath = "powershell.exe"
$serviceWrapperScriptPath = (Join-Path $MiholessInstallDirLocal "miholess_service_wrapper.ps1")
$serviceArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$serviceWrapperScriptPath`""

# Check if service exists and remove if Force is used
if (Invoke-MiholessServiceCommand -Command "query" -ServiceName $serviceName) {
    Write-Log "Service '${serviceName}' already exists. Stopping and removing old service..." "WARN"
    if (-not (Invoke-MiholessServiceCommand -Command "stop" -ServiceName $serviceName)) {
        Write-Log "Failed to stop existing service '${serviceName}'. Attempting to remove anyway." "WARN"
    }
    if (-not (Invoke-MiholessServiceCommand -Command "remove" -ServiceName $serviceName)) {
        Write-Log "Failed to remove existing service '${serviceName}'. Installation aborted." "ERROR"
        exit 1
    }
    Start-Sleep -Seconds 2 # Give it a moment to clean up
}

Write-Log "Creating Windows Service '${serviceName}'..."
try {
    if (-not (Invoke-MiholessServiceCommand -Command "create" -ServiceName $serviceName `
                                            -DisplayName $displayName -Description $description `
                                            -BinaryPathName "$serviceBinaryPath $serviceArguments" `
                                            -StartupType "auto")) {
        throw "Failed to create service using available methods."
    }
    
    # Set service dependencies (e.g., depends on network being available)
    # This specifically uses sc.exe as it's the reliable way for dependencies
    $dependCmd = "sc.exe config $serviceName depend= Nsi/TcpIp"
    Write-Log "Setting service dependency: $dependCmd"
    Invoke-Expression $dependCmd | Out-Null # Redirect output to null

    if (-not (Invoke-MiholessServiceCommand -Command "start" -ServiceName $serviceName)) {
        throw "Failed to start service using available methods."
    }

    Write-Log "Windows Service '${serviceName}' created and started successfully."
} catch {
    $errorMessage = $_.Exception.Message
    Write-Log "Failed to create or start Windows Service '${serviceName}': $errorMessage" "ERROR"
    exit 1
}


# 7. Create Scheduled Tasks
Write-Log "Creating scheduled tasks..."

# Function to safely register a scheduled task (local to install.ps1 as it's not in helper_functions yet)
# Note: This function should ideally be in helper_functions.ps1
# However, due to the order of operations (install script defines, then calls),
# it's safer to keep it here or ensure proper sourcing.
# Since helper_functions.ps1 is sourced *before* this function is called,
# it could theoretically be moved there. But for simplicity and self-containment
# within the installer's logic flow, it remains here.
function Register-MiholessScheduledTask {
    Param(
        [string]$TaskName,
        [string]$Description,
        [string]$ScriptPath, # Path received here is forward-slashed from config
        [ScheduledTaskTrigger[]]$Triggers,
        [ScheduledTaskSettingsSet]$Settings
    )
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Write-Log "Scheduled task '${TaskName}' already exists. Removing old task..." "WARN"
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    Write-Log "Registering scheduled task '${TaskName}'..."
    try {
        # ScriptPath for scheduled task needs system native backslashes
        $scriptPathLocal = $ScriptPath.Replace('/', '\')
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPathLocal`""
        Register-ScheduledTask -Action $action -Trigger $Triggers -TaskName $TaskName -Description $Description -Settings $Settings -Force
        Write-Log "Scheduled task '${TaskName}' registered successfully."
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to register scheduled task '${TaskName}': $errorMessage" "ERROR"
    }
}

$commonSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -StopIfGoingOnBatteries:$false -DontStopIfGoingOnBatteries -AllowStartOnDemand -Enabled -RunOnlyIfNetworkAvailable

# Task: Mihomo Core Updater
$taskNameCore = "Miholess_Core_Updater"
$scriptCorePath = "${MiholessInstallDir}/miholess_core_updater.ps1" # Use forward slashes as it comes from $MiholessInstallDir
$triggerCore = New-ScheduledTaskTrigger -Daily -At "03:00" # Run daily at 3 AM
Register-MiholessScheduledTask -TaskName $taskNameCore -Description "Updates Mihomo core to the latest non-Go version." `
    -ScriptPath $scriptCorePath -Triggers $triggerCore -Settings $commonSettings

# Task: Mihomo Config Updater
$taskNameConfig = "Miholess_Config_Updater"
$scriptConfigPath = "${MiholessInstallDir}/miholess_config_updater.ps1" # Use forward slashes
# Run every hour starting at midnight, duration 1 day (meaning it will run for 24 hours, then then repeat daily)
$triggerConfig = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1) -At "00:00" 
Register-MiholessScheduledTask -TaskName $taskNameConfig -Description "Updates Mihomo remote and local configurations." `
    -ScriptPath $scriptConfigPath -Triggers $triggerConfig -Settings $commonSettings

Write-Log "Scheduled tasks created successfully."

Write-Log "Miholess installation completed successfully!"
Write-Log "You can check service status with: Get-Service MiholessService"
Write-Log "And scheduled tasks with: Get-ScheduledTask -TaskName Miholess_*"
Write-Log "To configure, edit: ${ConfigFilePath}" # ConfigFilePath is already native, safe to use
