# Windows/miholess_service_wrapper.ps1
# This script is the entry point for the Windows service.
# It launches miholess.ps1 and handles its lifecycle.

# Determine the actual installation directory for proper log path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configFilePath = Join-Path $scriptDir "config.json" # configFilePath is native path
$helperFunctionsPath = Join-Path $scriptDir "helper_functions.ps1" # helperFunctionsPath is native path

# --- CRITICAL: Source helper_functions.ps1 immediately ---
if (Test-Path $helperFunctionsPath) { # Test-Path uses native path
    . $helperFunctionsPath
} else {
    # If helper_functions.ps1 is missing, we cannot log properly. Write to a fallback log and exit.
    $fallbackLogPath = "C:\ProgramData\miholess\bootstrap_service_wrapper_fatal.log" # Native path
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [FATAL] (Wrapper) helper_functions.ps1 not found at ${helperFunctionsPath}. Service cannot start. Exiting." | Out-File -FilePath $fallbackLogPath -Append -Encoding UTF8
    } catch {} # Suppress errors on fallback logging itself
    exit 1 # Critical failure, cannot proceed
}
# From this point, Write-Log is available and logs to file.

Write-Log "Wrapper: Service wrapper started. Attempting to load configuration from ${configFilePath}." "INFO"

# Load configuration using helper function. This also sets $script:config for Write-Log.
# Get-MiholessConfig expects native path
$config = Get-MiholessConfig -ConfigFilePath $configFilePath

if ($null -eq $config) {
    Write-Log "Wrapper: Failed to load configuration from ${configFilePath}. Service cannot start. Check config.json for syntax errors or missing file." "ERROR"
    exit 1 # Critical failure
}
# At this point, $script:config is set, and Write-Log will use its log_file or installation_dir.

# Convert paths from config (which are forward slashes) to native system backslashes for file operations
$miholessInstallationDirNative = $config.installation_dir.Replace('/', '\')
$mihomoScriptPath = (Join-Path $miholessInstallationDirNative "miholess.ps1")
$pidFilePath = (Join-Path $miholessInstallationDirNative "mihomo.pid")
$mihomoExePath = (Join-Path $miholessInstallationDirNative "mihomo.exe")

Write-Log "Wrapper: Configuration loaded successfully. Mihomo script path: ${mihomoScriptPath}" "INFO"

# Function to stop Mihomo process
function Stop-MihomoProcess {
    Param([string]$PidFilePath, [string]$MihomoExePath) # These are native paths
    Write-Log "Wrapper: Attempting to stop Mihomo process..."
    if (Test-Path $PidFilePath) { # Test-Path uses native path
        $mihomoPidContent = Get-Content -Path $PidFilePath -ErrorAction SilentlyContinue | Select-Object -First 1 # Renamed variable
        if ($mihomoPidContent -and $mihomoPidContent -match '^\d+$') {
            $mihomoPid = [int]$mihomoPidContent # Renamed variable
            try {
                $process = Get-Process -Id $mihomoPid -ErrorAction SilentlyContinue # Using renamed variable
                if ($process -and $process.ProcessName -eq "mihomo" -and $process.Path -eq $MihomoExePath) { # Process.Path is native path
                    Write-Log "Wrapper: Terminating Mihomo process with PID ${mihomoPid}." # Using renamed variable
                    $process | Stop-Process -Force
                    Remove-Item $PidFilePath -ErrorAction SilentlyContinue # Remove-Item uses native path
                    Write-Log "Wrapper: Mihomo process stopped via PID file."
                } else {
                    Write-Log "Wrapper: No active Mihomo process found with PID ${mihomoPid} matching expected path (${MihomoExePath}), or process name mismatch." "WARN" # Using renamed variable
                }
            } catch {
                $errorMessage = $_.Exception.Message
                Write-Log "Wrapper: Error stopping process with PID ${mihomoPid}: $errorMessage" "ERROR" # Using renamed variable
            }
        } else {
            Write-Log "Wrapper: Invalid or empty PID in ${PidFilePath}." "WARN"
        }
    } else {
        Write-Log "Wrapper: PID file not found (${PidFilePath})." "WARN"
    }

    # Fallback: kill any mihomo.exe instances from the installation directory
    try {
        Get-Process -Name "mihomo" -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $MihomoExePath } | Stop-Process -Force -ErrorAction SilentlyContinue # Where-Object uses native path
        Write-Log "Wrapper: Ensured any stray mihomo.exe instances from installation directory are stopped." "INFO"
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Wrapper: Error during fallback mihomo process termination: $errorMessage" "WARN"
    }
}

# Trap for service stop/shutdown events
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Log "Wrapper: PowerShell.Exiting event detected. Service is stopping. Initiating Mihomo shutdown." "INFO"
    Stop-MihomoProcess -PidFilePath $script:pidFilePath -MihomoExePath $script:mihomoExePath
    Write-Log "Wrapper: Mihomo shutdown complete. Service wrapper exiting." "INFO"
} | Out-Null


# Loop to keep Mihomo running
Write-Log "Wrapper: Entering main service loop. Will attempt to launch miholess.ps1." "INFO"
while ($true) {
    Write-Log "Wrapper: Attempting to launch miholess.ps1..." "INFO"
    try {
        # Arguments to Start-Process should use native paths for command line
        # $mihomoScriptPath is already a native path
        # Removed unsupported parameters: -PassThru, -NoNewWindow, -ErrorAction Stop
        # Rely on the service wrapper to ensure the launched PowerShell process stays hidden.
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$mihomoScriptPath`""
        
        # The line above does not return a process object.
        # So we cannot rely on $process.Id or $process.WaitForExit() here directly.
        # The outer service control manager will monitor the 'powershell.exe' process that *this* script starts.
        # We need to explicitly break the loop here and let the service wrapper exit,
        # otherwise, it will just keep re-launching `miholess.ps1` indefinitely.
        # This wrapper's role is to ensure `miholess.ps1` *starts*.
        # The monitoring of Mihomo's PID should be handled by `miholess.ps1` if it stays resident,
        # OR by the service manager if `miholess.ps1` exits immediately (which is our goal).

        # If Start-Process doesn't throw, we assume it launched successfully.
        Write-Log "Wrapper: miholess.ps1 launched (potentially hidden). Wrapper exiting to let service manager monitor the spawned process." "INFO"
        # The service itself will then monitor the "powershell.exe" process we just started,
        # and if it terminates, the service manager will restart this wrapper.
        # This is the standard behavior for Type=simple services where ExecStart is a long-running process.
        exit 0 # Exit successfully, letting the service manager continue.

    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Wrapper: Failed to launch miholess.ps1: $errorMessage. Restarting wrapper in 5 seconds." "ERROR"
    }
    
    Start-Sleep -Seconds 5
}
