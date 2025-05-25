# Windows/helper_functions.ps1

# Define a default log path for background scripts. This path will be used if a more specific path
# from config.json cannot be determined (e.g., during early script startup).
$global:MiholessDefaultServiceLogPath = "C:\ProgramData\miholess\miholess_service.log"

function Write-Log {
    Param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$Timestamp][$Level] $Message"
    
    # Always output to console for interactive debugging during installation
    $logEntry | Out-Host
    
    # Determine the log file path for background logging
    $targetLogFile = $global:MiholessDefaultServiceLogPath # Start with default fallback

    # Attempt to get the log file path from a loaded configuration
    # This requires the calling script (e.g., miholess_service_wrapper.ps1) to have loaded $config
    # and potentially set $script:config for global access.
    # We prioritize mihomo.log if it's explicitly set in config, otherwise use miholess_service.log.
    try {
        # Check if a global $config variable exists and has relevant properties
        if ($script:config -and $script:config.log_file -and ($script:config.log_file -ne (Join-Path $script:config.installation_dir "mihomo.log"))) {
            # Use Mihomo's specific log file if it's different from default
            $targetLogFile = $script:config.log_file
        } elseif ($script:config -and $script:config.installation_dir) {
            # Otherwise, use miholess_service.log within the installation directory
            $targetLogFile = Join-Path $script:config.installation_dir "miholess_service.log"
        }
    } catch {
        # Ignore errors if config isn't available yet or is malformed.
        # $targetLogFile will remain $global:MiholessDefaultServiceLogPath
    }

    # Ensure the directory for the log file exists
    $logDir = Split-Path $targetLogFile -Parent
    if (-not (Test-Path $logDir)) {
        try {
            New-Item -ItemType Directory -Path $logDir -ErrorAction Stop | Out-Null
        } catch {
            # If log directory cannot be created, output error to console and proceed without file logging
            $errorMessage = $_.Exception.Message # Capture error message reliably
            "[$Timestamp][ERROR] Failed to create log directory ${logDir}: $errorMessage" | Out-Host
            return # Skip file logging
        }
    }

    # Write to the log file
    try {
        $logEntry | Out-File -FilePath $targetLogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # If writing to file fails (e.g., permission denied), output to console as a last resort
        $errorMessage = $_.Exception.Message # Capture error message reliably
        "[$Timestamp][ERROR] Failed to write to log file ${targetLogFile}: $errorMessage" | Out-Host
    }
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
        
        # Load the configuration into a script-scope variable so Write-Log can access it
        $script:config = $expandedConfigContent | ConvertFrom-Json
        return $script:config
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
    Write-Log "DEBUG: API call successful for releases."

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
    Write-Log "DEBUG: Found $($assets.Count) assets."

    $osArchPattern = "mihomo-${OsType}-${Arch}"
    # Initialize $candidateUrls as an ArrayList to prevent unexpected type coercions
    [System.Collections.ArrayList]$candidateUrls = @() 

    foreach ($asset in $assets) {
        $assetName = $asset.name
        # Explicitly cast to string to ensure the download URL is always a string type
        [string]$downloadUrl = $asset.browser_download_url 

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
        
        Write-Log "DEBUG: Candidate - Asset: ${assetName}, URL: ${downloadUrl}"

        # Prioritize 'compatible' versions by adding them to the beginning
        if ($assetName -match 'compatible') {
            # Use ArrayList's Insert method and suppress its output
            $candidateUrls.Insert(0, $downloadUrl) | Out-Null
        } else {
            # Use ArrayList's Add method and suppress its output
            $candidateUrls.Add($downloadUrl) | Out-Null
        }
    }

    # Check count for ArrayList directly
    if ($candidateUrls.Count -eq 0) { 
        Write-Log "No suitable Mihomo binary found for ${OsType}-${Arch} (excluding Go versions: ${ExcludeGoVersions})." "ERROR"
        return $null
    }
    Write-Log "DEBUG: Found $($candidateUrls.Count) candidate URLs. First candidate: $($candidateUrls[0])"

    $finalUrl = $candidateUrls[0] # Get the highest priority URL

    # If a custom mirror is provided, replace the base GitHub URL
    if ($BaseMirror -ne "https://github.com/MetaCubeX/mihomo/releases/download/" -and $finalUrl -match "github.com/MetaCubeX/mihomo/releases/download/") {
        $relativePath = $finalUrl -replace "https://github.com/MetaCubeX/mihomo/releases/download/", ""
        $finalUrl = Join-Path -Path $BaseMirror -ChildPath $relativePath
        Write-Log "Using custom mirror: ${BaseMirror}"
    }
    
    Write-Log "DEBUG: Final URL before return: $finalUrl"
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
        $targetExeName = "mihomo.exe"
        $targetExePath = Join-Path $DestinationDir $targetExeName

        # Stop existing mihomo process if it's running from the target path
        if (Test-Path $targetExePath) {
            Write-Log "Existing ${targetExeName} found. Attempting to stop process before replacing..." "WARN"
            try {
                Get-Process -Name "mihomo" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path -eq $targetExePath } |
                    Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Log "Stopped existing mihomo process."
                Start-Sleep -Seconds 1
            } catch {
                $errorMessage = $_.Exception.Message
                Write-Log "Could not stop existing mihomo process. It might be in use: $errorMessage" "WARN"
            }
            Remove-Item $targetExePath -ErrorAction SilentlyContinue
        }

        # Expand the archive
        Expand-Archive -LiteralPath $zipFile -DestinationPath $DestinationDir -Force

        # Find the actual Mihomo executable after extraction
        # It might be named mihomo-windows-amd64-compatible.exe or mihomo.exe directly
        $extractedExe = Get-ChildItem -Path $DestinationDir -Filter "mihomo*.exe" -Recurse |
                        Where-Object { $_.Name -like "mihomo*${Arch}*.exe" -or $_.Name -eq "mihomo.exe" } |
                        Select-Object -First 1

        if ($extractedExe) {
            # If the found executable is not already named mihomo.exe and not in the root
            if ($extractedExe.Name -ne $targetExeName -or $extractedExe.DirectoryName -ne $DestinationDir) {
                Write-Log "Renaming and moving '${extractedExe.Name}' to '${targetExePath}'."
                Move-Item -Path $extractedExe.FullName -Destination $targetExePath -Force
                
                # Clean up empty parent directories if it was moved from a subfolder
                $parentDir = $extractedExe.Directory
                if ($parentDir.FullName -ne $DestinationDir -and (Get-ChildItem -Path $parentDir.FullName).Count -eq 0) {
                    Remove-Item -Path $parentDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            } else {
                 Write-Log "Mihomo executable found as ${targetExeName} in ${DestinationDir}."
            }
        } else {
            Write-Log "Could not find any mihomo executable (mihomo*.exe) after extraction in $DestinationDir." "ERROR"
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
            Write-Log "Downloading ${fileName} from $url"
            Invoke-WebRequest -Uri $url -OutFile $destination -ErrorAction Stop
        } catch {
            # Store exception message in a variable to avoid parsing issues
            $errorMessage = $_.Exception.Message
            Write-Log "Failed to download ${fileName}: $errorMessage" "WARN"
            $success = $false
        }
    }
    return $success
}


function Invoke-MiholessServiceCommand {
    Param(
        [string]$Command, # Valid commands: "query", "stop", "remove", "create", "start"
        [string]$ServiceName,
        [string]$DisplayName = "",
        [string]$Description = "",
        [string]$BinaryPathName = "", # For create command
        [string]$StartupType = "auto" # "auto", "demand", "disabled" for create command
    )

    Write-Log "Attempting service '$Command' for '$ServiceName'..."

    # Check for cmdlet availability
    $cmdletAvailable = $false
    switch ($Command) {
        "query"  { if (Get-Command -Name "Get-Service" -ErrorAction SilentlyContinue) { $cmdletAvailable = $true } }
        "stop"   { if (Get-Command -Name "Stop-Service" -ErrorAction SilentlyContinue) { $cmdletAvailable = $true } }
        "remove" { if (Get-Command -Name "Remove-Service" -ErrorAction SilentlyContinue) { $cmdletAvailable = $true } }
        "create" { if (Get-Command -Name "New-Service" -ErrorAction SilentlyContinue) { $cmdletAvailable = $true } }
        "start"  { if (Get-Command -Name "Start-Service" -ErrorAction SilentlyContinue) { $cmdletAvailable = $true } }
    }

    # Try PowerShell cmdlets first
    if ($cmdletAvailable) {
        try {
            switch ($Command) {
                "query" {
                    return (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null
                }
                "stop" {
                    Stop-Service -Name $ServiceName -Force -ErrorAction Stop
                    Write-Log "Service '${ServiceName}' stopped using cmdlet."
                    return $true
                }
                "remove" {
                    Remove-Service -Name $ServiceName -ErrorAction Stop
                    Write-Log "Service '${ServiceName}' removed using cmdlet."
                    return $true
                }
                "create" {
                    New-Service -Name $ServiceName -DisplayName $DisplayName -Description $Description `
                                -BinaryPathName $BinaryPathName -StartupType $StartupType -ErrorAction Stop
                    Write-Log "Service '${ServiceName}' created using cmdlet."
                    return $true
                }
                "start" {
                    # Set-Service is not directly for start, but for StartupType; Start-Service is for immediate start
                    # Also handles the case where service might be stopped already but we want to ensure it's running
                    Set-Service -Name $ServiceName -StartupType $StartupType -ErrorAction SilentlyContinue # Ensure startup type is set
                    Start-Service -Name $ServiceName -ErrorAction Stop
                    Write-Log "Service '${ServiceName}' started using cmdlet."
                    return $true
                }
            }
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Cmdlet for service '$Command' failed for '${ServiceName}': $errorMessage. Falling back to sc.exe." "WARN"
            # Fall through to sc.exe block
        }
    } else {
        Write-Log "Cmdlet for service '$Command' not found. Falling back to sc.exe." "WARN"
    }

    # Fallback to sc.exe
    try {
        switch ($Command) {
            "query" {
                $scResult = (sc.exe query `"$ServiceName`" 2>&1)
                return ($LASTEXITCODE -eq 0 -and $scResult -match "STATE") # Check if query successful and contains state
            }
            "stop" {
                $scResult = (sc.exe stop `"$ServiceName`" 2>&1)
                if ($LASTEXITCODE -eq 0 -or $scResult -match "STATE +: 1 +STOPPED") { # Check for success or already stopped
                    Write-Log "Service '${ServiceName}' stopped using sc.exe."
                    return $true
                } else {
                    throw "sc.exe stop command failed or service is not stopped: $scResult"
                }
            }
            "remove" {
                $scResult = (sc.exe delete `"$ServiceName`" 2>&1)
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Service '${ServiceName}' deleted using sc.exe."
                    return $true
                } else {
                    throw "sc.exe delete command failed: $scResult"
                }
            }
            "create" {
                $scResult = (sc.exe create `"$ServiceName`" binPath= `"$BinaryPathName`" DisplayName= `"$DisplayName`" start= `"$StartupType`" 2>&1)
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Service '${ServiceName}' created using sc.exe."
                    # Set description separately as part of create. sc.exe description command.
                    & sc.exe description $ServiceName "$Description" | Out-Null
                    return $true
                } else {
                    throw "sc.exe create command failed: $scResult"
                }
            }
            "start" {
                $scResult = (sc.exe start `"$ServiceName`" 2>&1)
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Service '${ServiceName}' started using sc.exe."
                    return $true
                } else {
                    throw "sc.exe start command failed: $scResult"
                }
            }
            default {
                Write-Log "Unsupported service command for sc.exe: $Command" "ERROR"
                return $false
            }
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Final attempt with sc.exe for service '$Command' for '${ServiceName}' failed: $errorMessage" "ERROR"
        return $false
    }
}


function Restart-MiholessService {
    Param([string]$ServiceName = "MiholessService")
    Write-Log "Attempting to restart Miholess service..."
    try {
        if (Invoke-MiholessServiceCommand -Command "query" -ServiceName $ServiceName) {
            Write-Log "Service '${ServiceName}' found. Stopping..."
            if (-not (Invoke-MiholessServiceCommand -Command "stop" -ServiceName $ServiceName)) {
                Write-Log "Failed to stop service '${ServiceName}'. Cannot restart." "ERROR"
                return $false
            }
            Start-Sleep -Seconds 2 # Give it time to fully stop
            Write-Log "Starting service '${ServiceName}'..."
            if (Invoke-MiholessServiceCommand -Command "start" -ServiceName $ServiceName) {
                Write-Log "Miholess service restarted successfully."
                return $true
            } else {
                Write-Log "Failed to start service '${ServiceName}'." "ERROR"
                return $false
            }
        } else {
            Write-Log "Miholess service '${ServiceName}' not found. Cannot restart." "WARN"
            return $false
        }
    } catch {
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
        Write-Log "Local config directory not found: ${LocalConfigPath}. Creating it." "INFO" # <-- FIX: ${LocalConfigPath}
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
    Write-Log "Downloading remote config from: ${RemoteConfigUrl} to ${targetConfigFilePath}"


    $newConfigContent = $null
    try {
        $newConfigContent = Invoke-WebRequest -Uri $RemoteConfigUrl -UseBasicParsing -ErrorAction Stop | Select-Object -ExpandProperty Content
    } catch {
        # Store exception message in a variable to avoid parsing issues
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to download remote config from ${RemoteConfigUrl}: $errorMessage" "ERROR"
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
            Write-Log "Failed to read existing config at ${targetConfigFilePath}: $errorMessage" "WARN"
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
