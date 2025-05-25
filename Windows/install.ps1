# Windows/install.ps1
# This script performs the interactive installation. It is meant to be called directly via irm | iex.

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
$InstallDirInput = Read-Host "Enter installation directory (Default: $Default_InstallDir)"
if ([string]::IsNullOrEmpty($InstallDirInput)) { $InstallDirInput = $Default_InstallDir }
# Store forward-slashed path for JSON/config, and native path for file system operations
$global:MiholessInstallDirJson = ([System.Environment]::ExpandEnvironmentVariables($InstallDirInput)).Replace('\', '/')
$global:MiholessInstallDirNative = $global:MiholessInstallDirJson.Replace('/', '\')
Write-Log-Temp "Installation Directory: ${global:MiholessInstallDirNative}" # Log native path

# Ensure the installation directory exists before attempting to download helper functions into it
if (-not (Test-Path -Path $global:MiholessInstallDirNative)) {
    Write-Log-Temp "Creating installation directory: ${global:MiholessInstallDirNative}"
    New-Item -ItemType Directory -Path $global:MiholessInstallDirNative | Out-Null
} else {
    Write-Log-Temp "Installation directory already exists. Proceeding with potential re-installation." "WARN"
}

# --- Download helper_functions.ps1 and source it ---
# This assumes helper_functions.ps1 is still online in the repo and copied from there.
# It ensures any helper function changes are picked up without requiring an update to install.ps1 itself.
$helperFunctionsUrl = "https://raw.githubusercontent.com/zx900930/miholess/main/Windows/helper_functions.ps1"
$helperFunctionsPath = Join-Path $global:MiholessInstallDirNative "helper_functions.ps1" # Use native path for download destination
Write-Log-Temp "Downloading helper_functions.ps1 to ${helperFunctionsPath}..."
try {
    # Ensure TLS 1.2 is enabled for the download
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
$LocalConfigPathInput = Read-Host "Enter local configuration folder path (e.g., %USERPROFILE%/my_configs. Default: $($Default_LocalConfigPath))"
if ([string]::IsNullOrEmpty($LocalConfigPathInput)) { $LocalConfigPathInput = $Default_LocalConfigPath }
# Store forward-slashed path for JSON/config, and native path for file system operations
$global:MiholessLocalConfigPathJson = ([System.Environment]::ExpandEnvironmentVariables($LocalConfigPathInput)).Replace('\', '/')
$global:MiholessLocalConfigPathNative = $global:MiholessLocalConfigPathJson.Replace('/', '\')
# FIX: Ensure LocalConfigPathNative is not empty. If it becomes empty after expansion/replace, set a fallback.
if ([string]::IsNullOrEmpty($global:MiholessLocalConfigPathNative)) {
    $global:MiholessLocalConfigPathNative = ([System.Environment]::ExpandEnvironmentVariables($Default_LocalConfigPath)).Replace('\', '\')
    Write-Log "Local Config Path was empty after expansion, set to default: ${global:MiholessLocalConfigPathNative}" "WARN"
}
Write-Log "Local Config Path: ${global:MiholessLocalConfigPathNative}" # Log native path

# 8. Get Mihomo Port
$MihomoPort = Read-Host "Enter Mihomo listen port (Default: $Default_MihomoPort)"
if ([string]::IsNullOrEmpty($MihomoPort)) { $MihomoPort = $Default_MihomoPort }
Write-Log "Mihomo Port: $MihomoPort"

# 9. Force Re-installation
$ForceInput = Read-Host "Force re-installation if Miholess already exists? (Y/N, Default: N)"
$Force = ($ForceInput -eq 'Y' -or $ForceInput -eq 'y')
Write-Log "Force Re-installation: $Force"

Write-Host "`n--- Installation Summary ---" -ForegroundColor Yellow
Write-Host "Installation Directory: ${global:MiholessInstallDirNative}"
Write-Host "Mihomo Core Mirror: $CoreMirror"
Write-Host "GeoIP URL: $GeoIpUrl"
Write-Host "GeoSite URL: $GeoSiteUrl"
Write-Host "MMDB URL: $MmdbUrl"
Write-Host "Remote Config URL: $($RemoteConfigUrl -replace '^$', '<empty>') (Will be downloaded to ${global:MiholessLocalConfigPathNative}\config.yaml)"
Write-Host "Local Config Path: ${global:MiholessLocalConfigPathNative} (Mihomo data directory)"
Write-Host "Mihomo Port: $MihomoPort"
Write-Host "Force Re-installation: $Force"
Write-Host "`nPress Enter to proceed with installation, or Ctrl+C to cancel." -ForegroundColor Green
Pause | Out-Null # Wait for user to press enter

# --- Populate final configuration hashtable ---
# All paths in this hashtable use forward slashes for JSON safety
$ConfigToSave = @{
    installation_dir = $global:MiholessInstallDirJson
    mihomo_core_mirror = $CoreMirror
    geoip_url = $GeoIpUrl
    geosite_url = $GeoSiteUrl
    mmdb_url = $MmdbUrl
    remote_config_url = $RemoteConfigUrl
    local_config_path = $global:MiholessLocalConfigPathJson
    log_file = "${global:MiholessInstallDirJson}/mihomo.log"
    pid_file = "${global:MiholessInstallDirJson}/mihomo.pid" # PID file will still be written by miholess.ps1 for updates
    mihomo_port = $MihomoPort
}

$MiholessServiceAccount = "NT AUTHORITY\System" # Remains constant

# 1. (Re-check) Create installation directory - now using $global:MiholessInstallDirNative
if (-not (Test-Path -Path $global:MiholessInstallDirNative)) {
    Write-Log "Creating installation directory: ${global:MiholessInstallDirNative} (Safety check)"
    New-Item -ItemType Directory -Path $global:MiholessInstallDirNative | Out-Null
} else {
    if ($Force) {
        Write-Log "Installation directory already exists. Forcing re-installation (confirmed)."
    } else {
        Write-Log "Installation directory already exists and not forcing re-installation. Exiting." "ERROR"
        exit 1
    }
}

# 2. Save configuration to JSON file
$ConfigFilePath = Join-Path $global:MiholessInstallDirNative "config.json" # Use native path for file system
Write-Log "Saving configuration to ${ConfigFilePath}"
$ConfigToSave | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigFilePath -Encoding UTF8

# 3. Download and Extract Mihomo Core
$mihomoDownloadUrl = Get-LatestMihomoDownloadUrl -OsType "windows" -Arch "amd64" -BaseMirror $CoreMirror
if ($null -eq $mihomoDownloadUrl) {
    Write-Log "Failed to get Mihomo download URL. Installation aborted." "ERROR"
    exit 1
}

# Pass native path for DestinationDir
if (-not (Download-AndExtractMihomo -DownloadUrl $mihomoDownloadUrl -DestinationDir $global:MiholessInstallDirNative)) {
    Write-Log "Failed to download and extract Mihomo. Installation aborted." "ERROR"
    exit 1
}

# 4. Download GeoIP, GeoSite, MMDB files
# IMPORTANT: Download to the Mihomo data directory ($global:MiholessLocalConfigPathNative)
# not the installation directory.
if ([string]::IsNullOrEmpty($global:MiholessLocalConfigPathNative)) {
    Write-Log "Error: Local config path is empty. Cannot download geodata files." "ERROR"
    exit 1 # Critical failure, cannot proceed without a valid local config path
}
if (-not (Download-MihomoDataFiles -DestinationDir $global:MiholessLocalConfigPathNative -GeoIpUrl $GeoIpUrl -GeoSiteUrl $GeoSiteUrl -MmdbUrl $MmdbUrl)) {
    Write-Log "Some data files failed to download. Check logs for details." "WARN"
}

# 5. Download NSSM and other scripts to installation directory
Write-Log "Downloading NSSM and Miholess scripts to ${global:MiholessInstallDirNative}..."

# NSSM Download URL from your GitHub repository (assuming it's placed in Windows/nssm/)
$nssmRepoUrl = "https://github.com/zx900930/miholess/raw/main/Windows/nssm/nssm.exe" # Use raw link
$nssmExePath = Join-Path $global:MiholessInstallDirNative "nssm.exe" # Target path for nssm.exe

try {
    Write-Log "Downloading NSSM from $nssmRepoUrl..."
    (New-Object System.Net.WebClient).DownloadFile($nssmRepoUrl, $nssmExePath) # Directly download nssm.exe
    Write-Log "NSSM downloaded to ${nssmExePath}."
} catch {
    $errorMessage = $_.Exception.Message
    Write-Log "Failed to download NSSM from repository: $errorMessage. Ensure nssm.exe is committed to ${nssmRepoUrl}." "ERROR"
    exit 1
}


# Download other Miholess scripts
# helper_functions.ps1 is already downloaded and sourced
$scriptsToDownload = @(
    "miholess_core_updater.ps1",
    "miholess_config_updater.ps1",
    "miholess.ps1", # miholess.ps1 will be used for config updates, not service run
    "uninstall.ps1" # Ensure uninstall script is present
)
foreach ($script in $scriptsToDownload) {
    # Assume these scripts are in the same directory as install.ps1 on GitHub
    $sourceUrl = "https://raw.githubusercontent.com/zx900930/miholess/main/Windows/$script"
    # Ensure destPath uses system native backslashes for file operation
    $destPath = (Join-Path $global:MiholessInstallDirNative $script)
    Write-Log "Downloading '${script}' from '${sourceUrl}' to '${destPath}'..."
    try {
        (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destPath)
        Write-Log "Downloaded '${script}'."
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Warning: Failed to download '${script}' from '${sourceUrl}': $errorMessage. Skipping." "WARN"
    }
}


# 6. Create Windows Service using NSSM
$serviceName = "MiholessService"
$displayName = "Miholess Core Service"
$description = "Manages Mihomo core and configurations, ensures autostart."
# NSSM will execute mihomo.exe directly
$nssmAppPath = Join-Path $global:MiholessInstallDirNative "mihomo.exe"
# Mihomo arguments: -f <config_path> -d <data_dir>
$mihomoMainConfigPathNative = (Join-Path $global:MiholessLocalConfigPathNative "config.yaml")
$mihomoDataDirNative = $global:MiholessLocalConfigPathNative
$nssmAppArgs = "-f `"${mihomoMainConfigPathNative}`" -d `"${mihomoDataDirNative}`""
# Mihomo's working directory should be its own executable directory
$mihomoWorkingDirectory = $global:MiholessInstallDirNative 
$mihomoLogPathNative = $ConfigToSave.log_file.Replace('/', '\') # Mihomo's log path from config

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

Write-Log "Creating Windows Service '${serviceName}' using NSSM to run Mihomo directly..."
try {
    # NSSM install command
    & "${nssmExePath}" install "${serviceName}" "${nssmAppPath}" "${nssmAppArgs}" | Out-Null

    # NSSM service configuration
    & "${nssmExePath}" set "${serviceName}" DisplayName "${displayName}" | Out-Null
    & "${nssmExePath}" set "${serviceName}" Description "${description}" | Out-Null
    & "${nssmExePath}" set "${serviceName}" AppDirectory "${mihomoWorkingDirectory}" | Out-Null # Set working directory for mihomo.exe
    & "${nssmExePath}" set "${serviceName}" AppStdout "${mihomoLogPathNative}" | Out-Null # Redirect stdout to Mihomo's log
    & "${nssmExePath}" set "${serviceName}" AppStderr "${mihomoLogPathNative}" | Out-Null # Redirect stderr to Mihomo's log
    & "${nssmExePath}" set "${serviceName}" AppStdoutCreationDisposition 4 | Out-Null # Always create/overwrite log
    & "${nssmExePath}" set "${serviceName}" AppStderrCreationDisposition 4 | Out-Null # Always create/overwrite log
    & "${nssmExePath}" set "${serviceName}" AppRestartDelay 5000 | Out-Null # Restart after 5 seconds if crashes
    & "${nssmExePath}" set "${serviceName}" AppThrottle 5000 | Out-Null # Prevent rapid restarts
    & "${nssmExePath}" set "${serviceName}" AppExitAction Restart | Out-Null # Always restart on exit
    & "${nssmExePath}" set "${serviceName}" Start "SERVICE_AUTO_START" | Out-Null # Set startup type to Automatic

    # Set service dependencies (still using sc.exe as NSSM doesn't have direct command for this)
    $dependCmd = "sc.exe config $serviceName depend= Nsi/TcpIp"
    Write-Log "Setting service dependency: $dependCmd"
    Invoke-Expression $dependCmd | Out-Null

    # Before starting service, ensure initial config.yaml is ready for Mihomo
    Write-Log "Ensuring initial config.yaml is ready for Mihomo service..."
    if (-not (Update-MihomoMainConfig -RemoteConfigUrl $RemoteConfigUrl -LocalConfigPath $global:MiholessLocalConfigPathNative)) {
        Write-Log "Failed to prepare initial Mihomo configuration. Service might not start correctly." "ERROR"
        # Not exiting here as service creation might still be useful for manual debug
    }


    # Start the service
    if (-not (Invoke-MiholessServiceCommand -Command "start" -ServiceName $serviceName)) {
        throw "Failed to start service using available methods."
    }

    Write-Log "Windows Service '${serviceName}' created and started successfully using NSSM."
} catch {
    $errorMessage = $_.Exception.Message
    Write-Log "Failed to create or start Windows Service '${serviceName}': $errorMessage" "ERROR"
    exit 1
}


# 7. Create Scheduled Tasks
Write-Log "Creating scheduled tasks..."

# Function to safely register a scheduled task (local to install.ps1)
# Now uses schtasks.exe command line with proper argument passing
function Register-MiholessScheduledTask {
    Param(
        [string]$TaskName,
        [string]$Description,
        [string]$ScriptPath, # Path received here is forward-slashed from config
        [string]$ScheduleType, # "DAILY", "HOURLY"
        [string]$ScheduleTime # "03:00", or "00:00" for hourly start
    )
    
    Write-Log "Attempting to register scheduled task '${TaskName}' using schtasks.exe..."

    # Check if task exists and remove if so
    try {
        $taskQuery = (schtasks.exe /query /TN `"${TaskName}`" /FO LIST 2>&1)
        if ($LASTEXITCODE -eq 0) { # Task exists
            Write-Log "Scheduled task '${TaskName}' already exists. Deleting old task." "WARN"
            # Use separate args for schtasks.exe /delete
            (schtasks.exe /delete /TN `"${TaskName}`" /F 2>&1) | Out-Null
            Start-Sleep -Seconds 1 # Give it a moment to clear
        }
    } catch {
        Write-Log "Error querying task '${TaskName}': $($_.Exception.Message)" "WARN"
    }

    # ScriptPath for scheduled task needs system native backslashes
    $scriptPathLocal = $ScriptPath.Replace('/', '\')
    $taskAction = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPathLocal`""
    
    try {
        # Build argument list for schtasks.exe /create
        $schtasksArgs = @(
            "/create",
            "/TN", "${TaskName}",
            "/TR", "`"$taskAction`"" # Action wrapped in double quotes for schtasks.exe
        )

        switch ($ScheduleType) {
            "DAILY" {
                $schtasksArgs += "/SC", "DAILY", "/ST", "${ScheduleTime}"
            }
            "HOURLY" {
                # schtasks.exe /SC HOURLY works without /MO and implies every hour
                # Combined with /ST, it means every hour starting at ST.
                $schtasksArgs += "/SC", "HOURLY", "/ST", "${ScheduleTime}"
            }
            default {
                Write-Log "Unsupported schedule type: ${ScheduleType}" "ERROR"
                return $false
            }
        }
        
        # Add common settings. /IT is needed for interactive tasks, /RL HIGHEST for admin context.
        # /F for force, /RU SYSTEM for System account.
        $schtasksArgs += "/RL", "HIGHEST"
        $schtasksArgs += "/IT" # Run only when user is logged on and allows interaction
        $schtasksArgs += "/F"
        $schtasksArgs += "/RU", "SYSTEM" # Run as System account

        # Execute schtasks.exe with the argument array
        Write-Log "Executing schtasks command: schtasks.exe $($schtasksArgs -join ' ')" "DEBUG"
        $result = (& schtasks.exe $schtasksArgs 2>&1)
        
        if ($LASTEXITCODE -eq 0 -and $result -match "SUCCESS") {
            Write-Log "Scheduled task '${TaskName}' registered successfully using schtasks.exe."
            return $true
        } else {
            throw "schtasks.exe /create command failed: $result"
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to register scheduled task '${TaskName}': $errorMessage" "ERROR"
        return $false
    }
}

$taskNameCore = "Miholess_Core_Updater"
$scriptCorePath = "${global:MiholessInstallDirJson}/miholess_core_updater.ps1"
$triggerCore = New-ScheduledTaskTrigger -Daily -At "03:00" # Dummy trigger var, not used directly by schtasks

Register-MiholessScheduledTask -TaskName $taskNameCore -Description "Updates Mihomo core to the latest non-Go version." `
    -ScriptPath $scriptCorePath -ScheduleType "DAILY" -ScheduleTime "03:00"

$taskNameConfig = "Miholess_Config_Updater"
$scriptConfigPath = "${global:MiholessInstallDirJson}/miholess_config_updater.ps1"
$triggerConfig = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1) -At "00:00" # Dummy trigger var

Register-MiholessScheduledTask -TaskName $taskNameConfig -Description "Updates Mihomo remote and local configurations." `
    -ScriptPath $scriptConfigPath -ScheduleType "HOURLY" -ScheduleTime "00:00" # Runs hourly starting at midnight

Write-Log "Scheduled tasks created successfully."

Write-Log "Miholess installation completed successfully!"
Write-Log "You can check service status with: Get-Service MiholessService"
Write-Log "And scheduled tasks with: schtasks.exe /query /TN Miholess_* /FO LIST"
Write-Log "To configure, edit: ${ConfigFilePath}"
