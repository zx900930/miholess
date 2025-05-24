# Windows/miholess_service_wrapper.ps1
# This script is the entry point for the Windows service.
# It launches miholess.ps1 and handles its lifecycle.

# --- Sourcing helper functions ---
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $PSScriptRoot "helper_functions.ps1")

$configFilePath = Join-Path $PSScriptRoot "config.json"
$config = Get-MiholessConfig -ConfigFilePath $configFilePath

if ($null -eq $config) {
    Write-Log "Wrapper: Failed to load configuration. Service cannot start." "ERROR"
    exit 1
}

$mihomoScriptPath = Join-Path $config.installation_dir "miholess.ps1"
$pidFilePath = $config.pid_file
$mihomoExePath = Join-Path $config.installation_dir "mihomo.exe" # For direct kill if needed

Write-Log "Wrapper: Miholess service wrapper started."

# Function to stop Mihomo process
function Stop-MihomoProcess {
    Param([string]$PidFilePath, [string]$MihomoExePath)
    Write-Log "Wrapper: Attempting to stop Mihomo process..."
    if (Test-Path $PidFilePath) {
        $pid = Get-Content -Path $PidFilePath | Select-Object -First 1
        if ($pid -and $pid -match '^\d+$') {
            try {
                $process = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
                if ($process -and $process.ProcessName -eq "mihomo") {
                    Write-Log "Wrapper: Terminating Mihomo process with PID $pid."
                    $process | Stop-Process -Force
                    Remove-Item $PidFilePath -ErrorAction SilentlyContinue
                    Write-Log "Wrapper: Mihomo process stopped."
                } else {
                    Write-Log "Wrapper: No active Mihomo process found with PID $pid." "WARN"
                }
            } catch {
                Write-Log "Wrapper: Error stopping process with PID $pid: $($_.Exception.Message)" "ERROR"
            }
        } else {
            Write-Log "Wrapper: Invalid PID in $PidFilePath." "WARN"
        }
    } else {
        Write-Log "Wrapper: PID file not found ($PidFilePath)." "WARN"
    }

    # Fallback: kill any mihomo.exe instances
    try {
        Get-Process -Name "mihomo" -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $MihomoExePath } | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Log "Wrapper: Ensured all mihomo.exe instances from installation directory are stopped."
    } catch {
        Write-Log "Wrapper: Error during fallback mihomo process termination: $($_.Exception.Message)" "WARN"
    }
}

# Trap for service stop/shutdown events
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Log "Wrapper: PowerShell.Exiting event detected. Stopping Mihomo." "INFO"
    Stop-MihomoProcess -PidFilePath $script:pidFilePath -MihomoExePath $script:mihomoExePath
    # Perform any other cleanup
} | Out-Null


# Loop to keep Mihomo running
while ($true) {
    Write-Log "Wrapper: Launching miholess.ps1 to start Mihomo..."
    $process = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$mihomoScriptPath`"" `
        -PassThru `
        -WindowStyle Hidden # Hide the PowerShell window for the child script

    # Wait for the child process to exit, then restart it if it failed
    $process.WaitForExit()

    $exitCode = $process.ExitCode
    Write-Log "Wrapper: miholess.ps1 exited with code: $exitCode."

    # If the process exited gracefully (e.g., told to stop), we might want to break the loop
    # For a service, usually we want it to keep trying.
    # Customize this based on desired service behavior (e.g., max restarts, specific exit codes).
    
    # Clean up PID file if the child process exited
    Remove-Item $pidFilePath -ErrorAction SilentlyContinue

    Write-Log "Wrapper: Waiting 5 seconds before restarting miholess.ps1..."
    Start-Sleep -Seconds 5
}
