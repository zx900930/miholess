# Windows/miholess_service_wrapper.ps1
# This script is the entry point for the Windows service.
# It launches miholess.ps1 and handles its lifecycle.

# Determine the actual installation directory for proper log path
# This path derivation is crucial for finding helper_functions.ps1 and config.json
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configFilePath = Join-Path $scriptDir "config.json"
$helperFunctionsPath = Join-Path $scriptDir "helper_functions.ps1"

# --- CRITICAL: Source helper_functions.ps1 immediately ---
if (Test-Path $helperFunctionsPath) {
    . $helperFunctionsPath
} else {
    # If helper_functions.ps1 is missing, we cannot log properly. Write to a fallback log and exit.
    $fallbackLogPath = "C:\ProgramData\miholess\bootstrap_service_wrapper_fatal.log"
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [FATAL] (Wrapper) helper_functions.ps1 not found at $helperFunctionsPath. Service cannot start. Exiting." | Out-File -FilePath $fallbackLogPath -Append -Encoding UTF8
    } catch {} # Suppress errors on fallback logging itself
    exit 1 # Critical failure, cannot proceed
}
# From this point, Write-Log is available and logs to file.

Write-Log "Wrapper: Service wrapper started. Attempting to load configuration from $configFilePath." "INFO"

# Load configuration using helper function. This also sets $script:config for Write-Log.
$config = Get-MiholessConfig -ConfigFilePath $configFilePath

if ($null -eq $config) {
    Write-Log "Wrapper: Failed to load configuration from $configFilePath. Service cannot start. Check config.json for syntax errors or missing file." "ERROR"
    exit 1 # Critical failure
}
# At this point, $script:config is set, and Write-Log will use its log_file or installation_dir.

Write-Log "Wrapper: Configuration loaded successfully. Mihomo script path: $($config.installation_dir)\miholess.ps1" "INFO"

$mihomoScriptPath = Join-Path $config.installation_dir "miholess.ps1"
$pidFilePath = $config.pid_file
$mihomoExePath = Join-Path $config.installation_dir "mihomo.exe" # For direct kill if needed

# Function to stop Mihomo process (copied/adapted from previous helper_functions logic)
function Stop-MihomoProcess {
    Param([string]$PidFilePath, [string]$MihomoExePath)
    Write-Log "Wrapper: Attempting to stop Mihomo process..."
    if (Test-Path $PidFilePath) {
        $pidContent = Get-Content -Path $PidFilePath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pidContent -and $pidContent -match '^\d+$') {
            $pid = [int]$pidContent
            try {
                $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($process -and $process.ProcessName -eq "mihomo" -and $process.Path -eq $MihomoExePath) {
                    Write-Log "Wrapper: Terminating Mihomo process with PID $pid."
                    $process | Stop-Process -Force
                    Remove-Item $PidFilePath -ErrorAction SilentlyContinue
                    Write-Log "Wrapper: Mihomo process stopped via PID file."
                } else {
                    Write-Log "Wrapper: No active Mihomo process found with PID $pid matching expected path ($MihomoExePath), or process name mismatch." "WARN"
                }
            } catch {
                $errorMessage = $_.Exception.Message
                Write-Log "Wrapper: Error stopping process with PID $pid: $errorMessage" "ERROR"
            }
        } else {
            Write-Log "Wrapper: Invalid or empty PID in $PidFilePath." "WARN"
        }
    } else {
        Write-Log "Wrapper: PID file not found ($PidFilePath)." "WARN"
    }

    # Fallback: kill any mihomo.exe instances from the installation directory
    try {
        Get-Process -Name "mihomo" -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $MihomoExePath } | Stop-Process -Force -ErrorAction SilentlyContinue
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
        $process = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$mihomoScriptPath`"" `
            -PassThru `
            -WindowStyle Hidden ` # Hide the PowerShell window for the child script
            -ErrorAction Stop # Ensure errors from Start-Process are caught
        
        Write-Log "Wrapper: miholess.ps1 launched successfully with PID $($process.Id)." "INFO"

        # Wait for the child process to exit, then restart it if it failed
        $process.WaitForExit()

        $exitCode = $process.ExitCode
        Write-Log "Wrapper: miholess.ps1 exited with code: $exitCode." "INFO"

        # Clean up PID file if the child process exited
        Remove-Item $pidFilePath -ErrorAction SilentlyContinue
        
        # Log reason for restart
        if ($exitCode -ne 0) {
            Write-Log "Wrapper: miholess.ps1 exited with non-zero code ($exitCode). This indicates an error. Restarting in 5 seconds." "WARN"
        } else {
            Write-Log "Wrapper: miholess.ps1 exited gracefully (code $exitCode). Restarting in 5 seconds." "INFO"
        }

    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Wrapper: Failed to launch or monitor miholess.ps1: $errorMessage. Restarting in 5 seconds." "ERROR"
    }
    
    Start-Sleep -Seconds 5
}
