# Windows/miholess_core_updater.ps1
# This script is called by the scheduled task to update the Mihomo core.

# --- Sourcing helper functions ---
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $PSScriptRoot "helper_functions.ps1")

$configFilePath = Join-Path $PSScriptRoot "config.json"
$config = Get-MiholessConfig -ConfigFilePath $configFilePath

if ($null -eq $config) {
    Write-Log "Core Updater: Failed to load configuration. Exiting." "ERROR"
    exit 1
}

Write-Log "Core Updater: Starting Mihomo core update check..."

$currentMihomoExePath = Join-Path $config.installation_dir "mihomo.exe"
$currentMihomoVersion = "Unknown"

# Attempt to get current Mihomo version (assuming it supports -v or -v)
if (Test-Path $currentMihomoExePath) {
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
        Write-Log "Core Updater: Could not determine current Mihomo version: $($_.Exception.Message)" "WARN"
    }
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
    Write-Log "Core Updater: Could not parse latest version from URL: $latestDownloadUrl" "WARN"
}

Write-Log "Core Updater: Latest available Mihomo version: $latestVersion"

# Simple version comparison (e.g., 1.19.0 > 1.18.9)
# This is a basic string comparison, for more robust version comparisons, use System.Version
if ($currentMihomoVersion -ne "Unknown" -and $latestVersion -ne "Unknown") {
    try {
        $currentVer = [System.Version]$currentMihomoVersion.TrimStart('v')
        $latestVer = [System.Version]$latestVersion.TrimStart('v')
        
        if ($latestVer -gt $currentVer) {
            Write-Log "Core Updater: New Mihomo version ($latestVersion) is available! Current: $currentMihomoVersion" "INFO"
            if (Download-AndExtractMihomo -DownloadUrl $latestDownloadUrl -DestinationDir $config.installation_dir) {
                Write-Log "Core Updater: Mihomo core updated. Restarting service..."
                if (Restart-MiholessService) {
                    Write-Log "Core Updater: Service restarted after core update."
                } else {
                    Write-Log "Core Updater: Failed to restart service after core update. Please check manually." "ERROR"
                }
            } else {
                Write-Log "Core Updater: Failed to download and extract new Mihomo core." "ERROR"
            }
        } else {
            Write-Log "Core Updater: Mihomo core is already up-to-date ($currentMihomoVersion). No update needed." "INFO"
        }
    } catch {
        Write-Log "Core Updater: Error comparing versions. Proceeding with download anyway: $($_.Exception.Message)" "WARN"
        if (Download-AndExtractMihomo -DownloadUrl $latestDownloadUrl -DestinationDir $config.installation_dir) {
            Write-Log "Core Updater: Mihomo core updated (version comparison failed). Restarting service..."
            if (Restart-MiholessService) {
                Write-Log "Core Updater: Service restarted after core update."
            } else {
                Write-Log "Core Updater: Failed to restart service after core update. Please check manually." "ERROR"
            }
        }
    }
} else {
    Write-Log "Core Updater: Cannot determine current or latest version. Attempting to download latest anyway." "WARN"
    if (Download-AndExtractMihomo -DownloadUrl $latestDownloadUrl -DestinationDir $config.installation_dir) {
        Write-Log "Core Updater: Mihomo core updated (version comparison skipped). Restarting service..."
        if (Restart-MiholessService) {
            Write-Log "Core Updater: Service restarted after core update."
        } else {
            Write-Log "Core Updater: Failed to restart service after core update. Please check manually." "ERROR"
        }
    } else {
        Write-Log "Core Updater: Failed to download and extract new Mihomo core." "ERROR"
    }
}

Write-Log "Core Updater: Mihomo core update check finished."
