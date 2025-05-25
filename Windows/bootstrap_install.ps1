# Windows/bootstrap_install.ps1
# This script is a lightweight bootstrap to ensure install.ps1 runs reliably.
# Its primary job is to:
# 1. Set PowerShell execution policy and TLS protocol for the current process.
# 2. Download the main install.ps1 script to a temporary file.
# 3. Execute the temporary install.ps1 script.
# 4. Clean up the temporary file.

# Set execution policy and TLS protocol for this process
Set-ExecutionPolicy Bypass -Scope Process -Force | Out-Null # Suppress output
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

$installScriptUrl = 'https://raw.githubusercontent.com/zx900930/miholess/main/Windows/install.ps1'
$tempInstallScriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"

Write-Host "Miholess Bootstrap: Starting installation process..." -ForegroundColor Green

try {
    # Download install.ps1 to a temporary file
    Write-Host "Miholess Bootstrap: Downloading main installer script..." -ForegroundColor Cyan
    (New-Object System.Net.WebClient).DownloadFile($installScriptUrl, $tempInstallScriptPath)

    # Execute the downloaded installer script
    Write-Host "Miholess Bootstrap: Launching interactive installation..." -ForegroundColor Yellow
    & $tempInstallScriptPath # Execute the temporary file

} catch {
    Write-Host "Miholess Bootstrap: An error occurred: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Miholess Bootstrap: Please ensure you have network connectivity and run PowerShell as Administrator." -ForegroundColor Red
} finally {
    # Clean up temporary script file
    if (Test-Path $tempInstallScriptPath) {
        Write-Host "Miholess Bootstrap: Cleaning up temporary installer file..." -ForegroundColor DarkGray
        Remove-Item $tempInstallScriptPath -ErrorAction SilentlyContinue
    }
    Write-Host "Miholess Bootstrap: Finished." -ForegroundColor DarkGray
}
