# Windows/helper_functions.ps1

function Write-Log {
    Param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$Timestamp][$Level] $Message" | Out-Host
    # Optionally, write to a specific log file as well
    # $logFilePath = "C:\ProgramData\miholess\miholess_install.log" # Example log path
    # "$Timestamp [$Level] $Message" | Out-File -FilePath $logFilePath -Append -Encoding UTF8
}

function Get-MiholessConfig {
    Param([string]$ConfigFilePath)
    if (-not (Test-Path -Path $ConfigFilePath)) {
        Write-Log "Configuration file not found at $ConfigFilePath." "ERROR"
        return $null
    }
    try {
        # Expand environment variables in the config file
        $rawConfigContent = Get-Content -Path $ConfigFilePath | Out-String
        $expandedConfigContent = [System.Environment]::ExpandEnvironmentVariables($rawConfigContent)
        
        $configContent = $expandedConfigContent | ConvertFrom-Json
        return $configContent
    } catch {
        # Store exception message in a variable to avoid parsing issues
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to read or parse configuration file: $errorMessage" "ERROR"
        return $null
    }
}

function Get-LatestMihomoDownloadUrl {
    Param(
        [string]$OsType = "windows",
        [string]$Arch = "amd64",
        [switch]$ExcludeGoVersions = $true,
        [string]$BaseMirror = "https://github.com/MetaCubeX/mihomo/releases/download/"
    )
    Write-Log "Fetching latest Mihomo release info from GitHub API..."
    $apiUrl = "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"

    try {
        $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
    } catch {
        # Store exception message in a variable to avoid parsing issues
        $errorMessage = $_.Exception.Message
        Write-Log "Error fetching release info from GitHub API: $errorMessage" "ERROR"
        return $null
    }

    $tagName = $releaseInfo.tag_name
    if (-not $tagName) {
        Write-Log "Could not find tag_name in the latest release info." "ERROR"
        return $null
    }

    $assets = $releaseInfo.assets
    if (-not $assets) {
        Write-Log "No assets found for the latest release." "ERROR"
        return $null
    }

    $osArchPattern = "mihomo-$OsType-$Arch"
    $candidateUrls = @() # Array to hold potential candidate URLs

    foreach ($asset in $assets) {
        $assetName = $asset.name
        $downloadUrl = $asset.browser_download_url

        if (-not $assetName -or -not $downloadUrl) {
            continue
        }

        # Check for OS and Architecture
        if ($assetName -notmatch $osArchPattern) {
            continue
        }

        # Exclude Go version specific builds if requested
        if ($ExcludeGoVersions -and ($assetName -match '-go\d+\b')) {
            continue
        }

        # Prioritize 'compatible' versions by adding them to the beginning
        if ($assetName -match 'compatible') {
            $candidateUrls = $downloadUrl + $candidateUrls # Prepend
        } else {
            $candidateUrls += $downloadUrl # Append
        }
    }

    if (-not $candidateUrls) {
        Write-Log "No suitable Mihomo binary found for $OsType-$Arch (excluding Go versions: $ExcludeGoVersions)." "ERROR"
        return $null
    }

    $finalUrl = $candidateUrls[0] # Get the highest priority URL

    # If a custom mirror is provided, replace the base GitHub URL
    if ($BaseMirror -ne "https://github.com/MetaCubeX/mihomo/releases/download/" -and $finalUrl -match "github.com/MetaCubeX/mihomo/releases/download/") {
        $relativePath = $finalUrl -replace "https://github.com/MetaCubeX/mihomo/releases/download/", ""
        $finalUrl = Join-Path -Path $BaseMirror -ChildPath $relativePath
        Write-Log "Using custom mirror: $BaseMirror"
    }

    return $finalUrl
}

function Download-AndExtractMihomo {
    Param(
        [string]$DownloadUrl,
        [string]$DestinationDir
    )
    Write-Log "Downloading Mihomo from $DownloadUrl"
    $zipFile = Join-Path -Path $env:TEMP -ChildPath "mihomo_temp_$(Get-Random).zip" # Use random name to avoid conflicts

    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipFile -ErrorAction Stop
    } catch {
        # Store exception message in a variable to avoid parsing issues
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to download Mihomo: $errorMessage" "ERROR"
        return $false
    }

    Write-Log "Extracting Mihomo to $DestinationDir"
    try {
        # Ensure target executable is not in use before extraction
        $mihomoExePath = Join-Path $DestinationDir "mihomo.exe"
        if (Test-Path $mihomoExePath) {
            Write-Log "Existing mihomo.exe found. Attempting to stop process before replacing..." "WARN"
            try {
                $process = Get-Process -Name "mihomo" -ErrorAction SilentlyContinue
                if ($process) {
                    $process | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-Log "Stopped existing mihomo process."
                    Start-Sleep -Seconds 1
                }
            } catch {
                # Store exception message in a variable to avoid parsing issues
                $errorMessage = $_.Exception.Message
                Write-Log "Could not stop existing mihomo process. It might be in use: $errorMessage" "WARN"
            }
            Remove-Item $mihomoExePath -ErrorAction SilentlyContinue
        }

        Expand-Archive -LiteralPath $zipFile -DestinationPath $DestinationDir -Force
        # Find the actual Mihomo executable after extraction (might be in a subdir)
        $mihomoExe = Get-ChildItem -Path $DestinationDir -Filter "mihomo.exe" -Recurse | Select-Object -First 1
        if ($mihomoExe) {
            # If it's not directly in the destination dir, move it up
            if ($mihomoExe.DirectoryName -ne $DestinationDir) {
                Write-Log "Moving mihomo.exe from $($mihomoExe.DirectoryName) to $DestinationDir"
                Move-Item -Path $mihomoExe.FullName -Destination (Join-Path $DestinationDir "mihomo.exe") -Force
                # Clean up empty subdirectories if any
                $parentDir = $mihomoExe.Directory
                if ((Get-ChildItem -Path $parentDir.FullName).Count -eq 0) {
                    Remove-Item -Path $parentDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        } else {
            Write-Log "Could not find mihomo.exe after extraction." "ERROR"
            return $false
        }
    } catch {
        # Store exception message in a variable to avoid parsing issues
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to extract Mihomo: $errorMessage" "ERROR"
        return $false
    } finally {
        Remove-Item $zipFile -ErrorAction SilentlyContinue
    }

    Write-Log "Mihomo downloaded and extracted successfully."
    return $true
}

function Download-MihomoDataFiles {
    Param(
        [string]$InstallationDir,
        [string]$GeoIpUrl,
        [string]$GeoSiteUrl,
        [string]$MmdbUrl
    )
    Write-Log "Downloading data files..."
    $dataFiles = @{
        "geoip.dat" = $GeoIpUrl
        "geosite.dat" = $GeoSiteUrl
        "country.mmdb" = $MmdbUrl
    }
    $success = $true
    foreach ($fileName in $dataFiles.Keys) {
        $url = $dataFiles[$fileName]
        $destination = Join-Path $InstallationDir $fileName
        try {
            Write-Log "Downloading $fileName from $url"
            Invoke-WebRequest -Uri $url -OutFile $destination -ErrorAction Stop
        } catch {
            # Store exception message in a variable to avoid parsing issues
            $errorMessage = $_.Exception.Message
            Write-Log "Failed to download $fileName: $errorMessage" "WARN"
            $success = $false
        }
    }
    return $success
}

function Restart-MiholessService {
    Param([string]$ServiceName = "MiholessService")
    Write-Log "Attempting to restart Miholess service..."
    try {
        if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Start-Service -Name $ServiceName -ErrorAction Stop
            Write-Log "Miholess service restarted successfully."
            return $true
        } else {
            Write-Log "Miholess service '$ServiceName' not found. Cannot restart." "WARN"
            return $false
        }
    } catch {
        # Store exception message in a variable to avoid parsing issues
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to restart Miholess service: $errorMessage" "ERROR"
        return $false
    }
}

function Update-MihomoMainConfig {
    Param(
        [string]$RemoteConfigUrl,
        [string]$LocalConfigPath # This is now the target folder for config.yaml
    )
    Write-Log "Updating Mihomo main configuration from remote URL..."

    if ([string]::IsNullOrEmpty($RemoteConfigUrl)) {
        Write-Log "No remote configuration URL provided. Skipping config update." "INFO"
        return $false
    }
    if (-not (Test-Path -Path $LocalConfigPath)) {
        Write-Log "Local config directory not found: $LocalConfigPath. Creating it." "INFO"
        try {
            New-Item -ItemType Directory -Path $LocalConfigPath | Out-Null
        } catch {
            # Store exception message in a variable to avoid parsing issues
            $errorMessage = $_.Exception.Message
            Write-Log "Failed to create local config directory: $errorMessage" "ERROR"
            return $false
        }
    }

    $targetConfigFilePath = Join-Path $LocalConfigPath "config.yaml"
    Write-Log "Downloading remote config from: $RemoteConfigUrl to $targetConfigFilePath"

    $newConfigContent = $null
    try {
        $newConfigContent = Invoke-WebRequest -Uri $RemoteConfigUrl -UseBasicParsing -ErrorAction Stop | Select-Object -ExpandProperty Content
    } catch {
        # Store exception message in a variable to avoid parsing issues
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to download remote config from $RemoteConfigUrl: $errorMessage" "ERROR"
        return $false
    }

    if ([string]::IsNullOrEmpty($newConfigContent)) {
        Write-Log "Downloaded remote config is empty. Not updating existing config." "WARN"
        return $false
    }

    $existingConfigContent = ""
    if (Test-Path $targetConfigFilePath) {
        try {
            $existingConfigContent = (Get-Content -Path $targetConfigFilePath | Out-String).Trim()
        } catch {
            # Store exception message in a variable to avoid parsing issues
            $errorMessage = $_.Exception.Message
            Write-Log "Failed to read existing config at $targetConfigFilePath: $errorMessage" "WARN"
        }
    }

    if ($newConfigContent.Trim() -ne $existingConfigContent) {
        Write-Log "Configuration content changed. Saving new config..."
        try {
            $newConfigContent | Out-File -FilePath $targetConfigFilePath -Encoding UTF8 -Force
            Write-Log "Main Mihomo config saved to $targetConfigFilePath"
            return $true # Indicates a change was made
        } catch {
            # Store exception message in a variable to avoid parsing issues
            $errorMessage = $_.Exception.Message
            Write-Log "Failed to save final Mihomo config: $errorMessage" "ERROR"
            return $false
        }
    } else {
        Write-Log "Configuration content is identical. No change needed."
        return $false # Indicates no change
    }
}
