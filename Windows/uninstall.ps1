# Windows/uninstall.ps1

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

$DefaultMiholessInstallDir = "C:\ProgramData\miholess" # Default installation directory. Should match install.ps1 default.

# Check for Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script must be run with Administrator privileges. Please restart PowerShell as Administrator." "ERROR"
    exit 1
}

Write-Log "Starting Miholess uninstallation..."

# 1. Stop and remove Windows Service
$serviceName = "MiholessService"
# Path to NSSM executable (assume it's in the installation directory)
$nssmExePath = Join-Path $DefaultMiholessInstallDir "nssm.exe"

if (Invoke-MiholessServiceCommand -Command "query" -ServiceName $serviceName) {
    Write-Log "Stopping service '${serviceName}'..."
    if (-not (Invoke-MiholessServiceCommand -Command "stop" -ServiceName $serviceName)) {
        Write-Log "Failed to stop existing service '${serviceName}'. Attempting to remove anyway." "WARN"
    }
    Write-Log "Removing service '${serviceName}' using NSSM..."
    if (Test-Path $nssmExePath) {
        try {
            # Use & to execute nssm.exe and pipe output to Out-Null
            & "${nssmExePath}" stop "${serviceName}" | Out-Null # Ensure it's stopped via NSSM
            & "${nssmExePath}" remove "${serviceName}" confirm | Out-Null # Use 'confirm' for unattended removal
            Write-Log "Service '${serviceName}' removed successfully using NSSM."
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Failed to remove service '${serviceName}' using NSSM: $errorMessage. Falling back to sc.exe." "WARN"
            # Fallback to sc.exe if nssm removal fails
            if (Invoke-MiholessServiceCommand -Command "remove" -ServiceName $serviceName) {
                Write-Log "Service '${serviceName}' removed successfully using sc.exe fallback."
            } else {
                Write-Log "Failed to remove service '${serviceName}' with fallback. Manual removal might be required." "ERROR"
            }
        }
    } else {
        Write-Log "NSSM executable not found at ${nssmExePath}. Attempting removal using sc.exe fallback." "WARN"
        if (Invoke-MiholessServiceCommand -Command "remove" -ServiceName $serviceName) {
            Write-Log "Service '${serviceName}' removed successfully using sc.exe fallback."
        } else {
            Write-Log "Failed to remove service '${serviceName}' with fallback. Manual removal might be required." "ERROR"
        }
    }
} else {
    Write-Log "Service '${serviceName}' not found." "INFO"
}

# 2. Unregister Scheduled Tasks using schtasks.exe
$taskNames = @(
    "Miholess_Core_Updater",
    "Miholess_Config_Updater"
)
foreach ($taskName in $taskNames) {
    Write-Log "Attempting to unregister scheduled task '${taskName}' using schtasks.exe..."
    try {
        $taskQuery = (schtasks.exe /query /TN `"${taskName}`" /FO LIST 2>&1)
        if ($LASTEXITCODE -eq 0) { # Task exists
            $result = (schtasks.exe /delete /TN `"${taskName}`" /F 2>&1)
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Scheduled task '${taskName}' unregistered successfully using schtasks.exe."
            } else {
                throw "schtasks.exe /delete command failed: $result"
            }
        } else {
            Write-Log "Scheduled task '${taskName}' not found. Skipping unregistration." "INFO"
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to unregister scheduled task '${taskName}': $errorMessage" "ERROR"
    }
}

# 3. Delete installation directory
# Read installation_dir from config.json if it exists, otherwise use default
$MiholessInstallDirToDelete = $DefaultMiholessInstallDir # Start with default native path
$loadedConfig = Get-MiholessConfig -ConfigFilePath $configFilePath # Get-MiholessConfig expects native path
if ($loadedConfig -and $loadedConfig.installation_dir) {
    # Convert forward slashes from config to native backslashes for file system operations
    $MiholessInstallDirToDelete = $loadedConfig.installation_dir.Replace('/', '\')
    Write-Log "Using configured installation directory for uninstallation: ${MiholessInstallDirToDelete}"
} else {
    Write-Log "Could not load installation directory from config.json. Using default: ${MiholessInstallDirToDelete}" "WARN"
}

if (Test-Path -Path $MiholessInstallDirToDelete) { # Test-Path uses native path
    Write-Log "Deleting installation directory: ${MiholessInstallDirToDelete}"
    try {
        Remove-Item -Path $MiholessInstallDirToDelete -Recurse -Force -ErrorAction Stop # Remove-Item uses native path
        Write-Log "Installation directory removed successfully."
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to remove installation directory '${MiholessInstallDirToDelete}': $errorMessage" "ERROR"
    }
} else {
    Write-Log "Installation directory '${MiholessInstallDirToDelete}' not found." "INFO"
}

Write-Log "Miholess uninstallation completed."
