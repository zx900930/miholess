# Windows/uninstall.ps1

# --- Sourcing helper functions ---
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $PSScriptRoot "helper_functions.ps1")

$MiholessInstallDir = "C:\ProgramData\miholess" # Default installation directory

# Check for Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script must be run with Administrator privileges. Please restart PowerShell as Administrator." "ERROR"
    exit 1
}

Write-Log "Starting Miholess uninstallation..."

# 1. Stop and remove Windows Service
$serviceName = "MiholessService"
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    Write-Log "Stopping service '$serviceName'..."
    try {
        Stop-Service -Name $serviceName -Force -ErrorAction Stop
        Remove-Service -Name $serviceName -ErrorAction Stop
        Write-Log "Service '$serviceName' removed successfully."
    } catch {
        Write-Log "Failed to stop or remove service '$serviceName': $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "Service '$serviceName' not found." "INFO"
}

# 2. Unregister Scheduled Tasks
$taskNames = @(
    "Miholess_Core_Updater",
    "Miholess_Config_Updater"
)
foreach ($taskName in $taskNames) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Write-Log "Unregistering scheduled task '$taskName'..."
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Log "Scheduled task '$taskName' unregistered successfully."
        } catch {
            Write-Log "Failed to unregister scheduled task '$taskName': $($_.Exception.Message)" "ERROR"
        }
    } else {
        Write-Log "Scheduled task '$taskName' not found." "INFO"
    }
}

# 3. Delete installation directory
if (Test-Path -Path $MiholessInstallDir) {
    Write-Log "Deleting installation directory: $MiholessInstallDir"
    try {
        Remove-Item -Path $MiholessInstallDir -Recurse -Force -ErrorAction Stop
        Write-Log "Installation directory removed successfully."
    } catch {
        Write-Log "Failed to remove installation directory '$MiholessInstallDir': $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "Installation directory '$MiholessInstallDir' not found." "INFO"
}

Write-Log "Miholess uninstallation completed."
