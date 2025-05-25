# Windows/miholess_core_updater.ps1
# This script is called by the scheduled task to update the Mihomo core.

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

Write-Log "Core Updater: Starting Mihomo core update check." "INFO"

# Load configuration using helper function
$config = Get-MiholessConfig -ConfigFilePath $configFilePath # Get-MiholessConfig expects native path

if ($null -eq $config) {
    Write-Log "Core Updater: Failed to load configuration. Exiting." "ERROR"
    exit 1
}

# Convert paths from config (which are forward slashes) to native system backslashes for file operations
$miholessInstallationDirNative = $config.installation_dir.Replace('/', '\')
$currentMihomoExePath = (Join-Path $miholessInstallationDirNative "mihomo.exe")
$currentMihomoVersion = "Unknown"

# Attempt to get current Mihomo version (assuming it supports -v or -v)
Write-Log "Core Updater: Checking current Mihomo version from ${currentMihomoExePath}." "INFO"
if (Test-Path $currentMihomoExePath) { # Test-Path uses native path
    try {
        $mihomoOutput = & $currentMihomoExePath -v 2>&1 # Redirect stderr to stdout
        $versionMatch = $mihomoOutput | Select-String -Pattern "Version:\s*(\S+)"
        if ($versionMatch) {
            $currentMihomoVersion = $versionMatch.Matches[0].Groups[1].Value
        } else {
             $versionMatch = $mihomoOutput | Select-String -Pattern "mihomo\s*version\s*(\S+)"
             if ($versionMatch) {
                $currentMihomoVersion = $versionMatch.Matches[0].Groups[1].Value
             }
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Core Updater: Could not determine current Mihomo version: $errorMessage" "WARN"
    }
} else {
    Write-Log "Core Updater: Mihomo executable not found at ${currentMihomoExePath}." "WARN"
}
Write-Log "Core Updater: Current Mihomo version: $currentMihomoVersion"

$latestDownloadUrl = Get-LatestMihomoDownloadUrl `
    -OsType "windows" `
    -Arch "amd64" `
    -BaseMirror $config.mihomo_core_mirror

if ($null -eq $latestDownloadUrl) {
    Write-Log "Core Updater: Failed to get latest Mihomo download URL. Aborting update." "ERROR"
    exit 1
}

# Extract version from URL for comparison
$latestVersionMatch = $latestDownloadUrl | Select-String -Pattern "v(\d+\.\d+\.\d+)(?:\.\d+)?\.zip"
$latestVersion = "Unknown"
if ($latestVersionMatch) {
    $latestVersion = $latestVersionMatch.Matches[0].Groups[1].Value
} else {
    Write-Log "Core Updater: Could not parse latest version from URL: ${latestDownloadUrl}" "WARN"
}

Write-Log "Core Updater: Latest available Mihomo version: $latestVersion"

$coreUpdated = $false # Flag to track if core was updated

# Simple version comparison (e.g., 1.19.0 > 1.18.9)
if ($currentMihomoVersion -ne "Unknown" -and $latestVersion -ne "Unknown") {
    try {
        $currentVer = [System.Version]$currentMihomoVersion.TrimStart('v')
        $latestVer = [System.Version]$latestVersion.TrimStart('v')
        
        if ($latestVer -gt $currentVer) {
            Write-Log "Core Updater: New Mihomo version (${latestVersion}) is available! Current: ${currentMihomoVersion}" "INFO"
            # Pass native path for DestinationDir
            if (Download-AndExtractMihomo -DownloadUrl $latestDownloadUrl -DestinationDir $miholessInstallationDirNative) {
                Write-Log "Core Updater: Mihomo core updated."
                $coreUpdated = $true
            } else {
                Write-Log "Core Updater: Failed to download and extract new Mihomo core." "ERROR"
            }
        } else {
            Write-Log "Core Updater: Mihomo core is already up-to-date (${currentMihomoVersion}). No update needed." "INFO"
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Core Updater: Error comparing versions. Proceeding with download anyway: $errorMessage" "WARN"
        # Pass native path for DestinationDir
        if (Download-AndExtractMihomo -DownloadUrl $latestDownloadUrl -DestinationDir $miholessInstallationDirNative) {
            Write-Log "Core Updater: Mihomo core updated (version comparison failed)."
            $coreUpdated = $true
        } else {
            Write-Log "Core Updater: Failed to download and extract new Mihomo core." "ERROR"
        }
    }
} else {
    Write-Log "Core Updater: Cannot determine current or latest version. Attempting to download latest anyway." "WARN"
    # Pass native path for DestinationDir
    if (Download-AndExtractMihomo -DownloadUrl $latestDownloadUrl -DestinationDir $miholessInstallationDirNative) {
        Write-Log "Core Updater: Mihomo core updated (version comparison skipped)."
        $coreUpdated = $true
    } else {
        Write-Log "Core Updater: Failed to download and extract new Mihomo core." "ERROR"
    }
}

# After core update, always re-run miholess.ps1 to refresh config and PID file if necessary
# and then restart the service.
if ($coreUpdated) {
    Write-Log "Core Updater: Core was updated. Running miholess.ps1 for config/PID refresh and then restarting service." "INFO"
    $miholessSetupScriptPath = Join-Path $miholessInstallationDirNative "miholess.ps1"
    try {
        # Execute miholess.ps1 to ensure config/data are correct and PID is updated
        # This script runs config update logic and updates PID file, then exits.
        & "powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$miholessSetupScriptPath" | Out-Null
        Write-Log "Core Updater: miholess.ps1 executed for setup refresh."
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Core Updater: Failed to execute miholess.ps1 for setup refresh: $errorMessage." "ERROR"
    }

    if (Restart-MiholessService) {
        Write-Log "Core Updater: Service restarted after core update."
    } else {
        Write-Log "Core Updater: Failed to restart service after core update. Please check manually." "ERROR"
    }
}

Write-Log "Core Updater: Mihomo core update check finished."
