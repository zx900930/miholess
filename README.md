# miholess

```
 __    __  __  __  __  ______  __      ______  ______  ______
/\ "-./  \/\ \/\ \_\ \/\  __ \/\ \    /\  ___\/\  ___\/\  ___\
\ \ \-./\ \ \ \ \  __ \ \ \/\ \ \ \___\ \  __\\ \___  \ \___  \
 \ \_\ \ \_\ \_\ \_\ \_\ \_____\ \_____\ \_____\/\_____\/\_____\
  \/_/  \/_/\/_/\/_/\/_/\/_____/\/_____/\/_____/\/_____/\/_____/
```

![GitHub Workflow Status](https://img.shields.io/badge/status-work_in_progress-orange)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

`miholess` is a utility designed to simplify the management of the [Mihomo](https://github.com/MetaCubeX/mihomo) core, its associated data files (GeoIP, GeoSite, MMDB), and configuration files on both Windows and Linux systems. It automates the download, installation, and periodic updates, ensuring your Mihomo instance is always running the latest version with up-to-date rules and settings.

## Features

- **Automated Core Updates:** Automatically downloads the latest Mihomo core from GitHub releases, specifically avoiding `go` version-specific builds and prioritizing `compatible` versions.
- **Automated Data File Updates:** Keeps your `geoip.dat`, `geosite.dat`, and `country.mmdb` files up-to-date from specified URLs.
- **Automated Configuration Updates:** Downloads a remote configuration file and saves it as `config.yaml` within a specified local folder, which Mihomo then uses.
- **Cross-Platform Automation:**
  - **Windows:** Utilizes PowerShell, Windows Services for continuous operation, and Scheduled Tasks for periodic updates.
  - **Linux:** (Planned) Will use Bash scripts, systemd services, and cron jobs/systemd timers for equivalent functionality.
- **Customizable Sources:** Allows users to specify custom mirror URLs for Mihomo binaries and data files, as well as a custom remote configuration URL.
- **Flexible Configuration Management:** Use a single remote URL for your main configuration, or manage your `config.yaml` entirely locally.

## Project Structure

```
miholess/
├── README.md
├── LICENSE
├── config.example.json         # Example configuration file
├── Windows/
│   ├── install.ps1             # Main installation script
│   ├── uninstall.ps1           # Uninstallation script
│   ├── miholess_core_updater.ps1  # Script to update Mihomo core
│   ├── miholess_config_updater.ps1 # Script to update remote configurations
│   ├── miholess_service_wrapper.ps1 # Wrapper for the Windows Service
│   ├── miholess.ps1            # Main Mihomo execution script
│   └── helper_functions.ps1    # Common PowerShell functions
├── Linux/
│   ├── install.sh              # (Planned) Main installation script
│   ├── uninstall.sh            # (Planned) Uninstallation script
│   ├── miholess_core_updater.sh   # (Planned) Script to update Mihomo core
│   ├── miholess_config_updater.sh # (Planned) Script to update remote configurations
│   ├── miholess.service        # (Planned) systemd service unit file
│   └── miholess.sh             # (Planned) Main Mihomo execution script
```

## Installation

### Prerequisites

- **Windows:**
  - Windows 7 SP1 or later, Windows Server 2008 R2 SP1 or later.
  - PowerShell 5.1 or newer (PowerShell 7+ is recommended for best compatibility and features).
  - Administrator privileges are required for installation and uninstallation.
  - An active internet connection to download Mihomo and related files.

### Windows Installation

The `install.ps1` script is designed to be executed directly from a URL using `Invoke-Expression` (iex), or by downloading it locally and running it.

**Recommended (One-liner for fresh install):**

Open **PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; `
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; `
$tempPath = [System.IO.Path]::GetTempFileName() + ".ps1"; `
(New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/zx900930/miholess/main/Windows/install.ps1', $tempPath); `
& $tempPath; `
Remove-Item $tempPath -ErrorAction SilentlyContinue
```

_(Note: The backticks `` ` `` at the end of lines are for multi-line commands in PowerShell and can be removed if pasted as a single line.)_

**Explanation of the one-liner:**

- `Set-ExecutionPolicy Bypass -Scope Process -Force`: This temporarily sets the PowerShell execution policy to `Bypass` for the current PowerShell session (process), allowing the script to run without security prompts. The `-Force` parameter suppresses the confirmation message.
- `[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072`: This explicitly enables TLS 1.2 (value 3072) for web requests within the current session. This helps prevent issues when downloading files from HTTPS URLs, especially on older Windows versions.
- `$tempPath = [System.IO.Path]::GetTempFileName() + ".ps1";`: Generates a unique temporary file name with a `.ps1` extension to store the downloaded script.
- `(New-Object System.Net.WebClient).DownloadFile('...', $tempPath);`: Downloads the `install.ps1` script content from GitHub directly to the temporary file specified by `$tempPath`.
- `& $tempPath;`: Executes the downloaded script file. This is the most reliable way to execute a PowerShell script interactively.
- `Remove-Item $tempPath -ErrorAction SilentlyContinue`: Cleans up the temporary script file after the installation is complete.

**Interactive Setup Steps:**

Once the script starts, it will prompt you for the following information. Default values are provided in parentheses; press Enter to accept the default or type a new value.

- **Installation Directory:** Where Miholess and Mihomo files will be stored (e.g., `C:\ProgramData\miholess`).
- **Mihomo Core Download Mirror URL:** Base URL for Mihomo binary downloads. Use this for GitHub mirrors (e.g., `https://ghfast.top/https://github.com/MetaCubeX/mihomo/releases/download/`).
- **GeoIP.dat download URL**
- **GeoSite.dat download URL**
- **Country.mmdb download URL**
- **Remote configuration URL:** The URL of your main Mihomo configuration file. Leave empty if you manage `config.yaml` locally.
- **Local configuration folder path:** A folder where Mihomo's `config.yaml` (and potentially other data files) will reside (e.g., `%USERPROFILE%\miholess_local_configs`).
- **Mihomo listen port:** The port Mihomo will listen on (default: `7890`).
- **Force re-installation:** Choose Y/N if you want to overwrite an existing Miholess installation.

After you provide all details, a summary will be displayed, and you'll be asked to press Enter to confirm and proceed.

After installation, `miholess` will:

1.  Download the latest Mihomo core and required data files.
2.  Create a `config.json` file in the installation directory.
3.  Set up a Windows Service named `MiholessService` to ensure Mihomo runs automatically on system startup and restarts if it crashes.
4.  Create two Scheduled Tasks:
    - `Miholess_Core_Updater`: Runs daily at 3:00 AM to check for and update the Mihomo core.
    - `Miholess_Config_Updater`: Runs hourly to check for and update the remote configuration.

### Linux Installation (Planned)

_(This section will be filled once the Linux scripts are developed)_

## Configuration

All core settings for `miholess` are stored in a `config.json` file located in your `installation_dir` (default: `C:\ProgramData\miholess\config.json`).

You can view an example structure in `config.example.json` at the root of this repository.

**To modify the configuration:**

1.  Navigate to your Miholess installation directory (e.g., `C:\ProgramData\miholess`).
2.  Open `config.json` with a text editor (like Notepad or VS Code).
3.  Edit the values as needed. Note that environment variables like `%USERPROFILE%` will be expanded by the scripts when they read the config.
4.  **Important:** After modifying `config.json`, you should restart the `MiholessService` to apply changes.
    - Open **PowerShell as Administrator** and run:
      ```powershell
      Restart-Service MiholessService
      ```
    - Or, wait for the next scheduled config update (hourly).

**Key Configuration Parameters:**

- `"installation_dir"`: Path where Mihomo and its data/scripts are stored.
- `"mihomo_core_mirror"`: Base URL for downloading Mihomo binaries. Useful if GitHub is slow or blocked (e.g., `https://ghfast.top/https://github.com/MetaCubeX/mihomo/releases/download/`).
- `"geoip_url"`, `"geosite_url"`, `"mmdb_url"`: URLs for the respective data files.
- `"remote_config_url"`: The URL of your primary remote Mihomo configuration file (e.g., `https://example.com/your-main-config.yaml`).
  **Important:** The remote config fetched from this URL **must be a complete and valid Mihomo YAML configuration file**. It should include all necessary sections like `port`, `log-level`, `external-controller`, `proxies`, `proxy-groups`, `rules`, etc. `miholess` will download this file and save it directly as `config.yaml` in your `local_config_path` folder.
- `"local_config_path"`: A single folder path (e.g., `"%USERPROFILE%\my_configs"`).
  - If `remote_config_url` is provided, the `config.yaml` downloaded from there will be placed in this folder, overwriting any existing `config.yaml`.
  - If you **do not** wish to use a remote config URL, you can leave `remote_config_url` empty (`""`). In this case, you **must manually place your `config.yaml` file** directly inside this `local_config_path` folder. Mihomo will then use this local `config.yaml`.
- `"log_file"`: Path to Mihomo's log file.
- `"pid_file"`: Path to Mihomo's PID file (used internally by Miholess).
- `"mihomo_port"`: The port Mihomo will listen on (default: `7890`).

**Advanced Configuration Customization:**

If you are using a 3rd-party subscription config URL and wish to customize it before `miholess` uses it (e.g., add custom rules, modify proxy groups), you have a few options:

1.  **Use a Configuration Management Tool:** Projects like [Sub-Store](https://github.com/sub-store-org/Sub-Store) allow you to process and customize subscription links. You can then use the _output_ URL from such a tool as your `remote_config_url` in `miholess`.
2.  **Manual Local Configuration:** Leave the `remote_config_url` in `config.json` empty (`""`). Then, manually download your subscription config, customize it, and save it as `config.yaml` directly within your specified `local_config_path` folder. You will be responsible for updating this `config.yaml` manually when your subscription changes.

## Usage (After Installation)

Once installed, `miholess` operates largely in the background.

- **Mihomo Core:** Runs as a Windows Service (`MiholessService`) and starts automatically with Windows.
- **Updates:** Handled by scheduled tasks.
  - Core updates run daily.
  - Config updates run hourly.

### Checking Service Status (Windows)

Open PowerShell (as Administrator is best for full details):

```powershell
Get-Service MiholessService
```

### Checking Scheduled Tasks (Windows)

Open PowerShell:

```powershell
Get-ScheduledTask -TaskName Miholess_*
```

### Checking Mihomo Logs

You can find Mihomo's logs at the path specified in your `config.json` (default: `C:\ProgramData\miholess\mihomo.log`).

## Uninstallation

### Windows Uninstallation

Open **PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/zx900930/miholess/main/Windows/uninstall.ps1 | iex
```

This script will stop and remove the Windows Service, unregister the scheduled tasks, and delete the Miholess installation directory.

### Linux Uninstallation (Planned)

_(This section will be filled once the Linux scripts are developed)_

## Troubleshooting

- **"Script must be run with Administrator privileges"**: Ensure you open PowerShell by right-clicking its icon and selecting "Run as administrator".
- **Mihomo not running**:
  - Check `Get-Service MiholessService` status. If stopped, try `Start-Service MiholessService`.
  - Check the `mihomo.log` file in your installation directory for errors.
  - Ensure no other application is using Mihomo's configured port (`mihomo_port`).
  - Verify that a valid `config.yaml` exists in your `local_config_path` directory.
- **Updates not happening**:
  - Check `Get-ScheduledTask -TaskName Miholess_*` status and `LastRunResult`.
  - Manually trigger the updater scripts from the installation directory:
    - `& "C:\ProgramData\miholess\miholess_core_updater.ps1"`
    - `& "C:\ProgramData\miholess\miholess_config_updater.ps1"`
  - Check the logs for these scripts (they output to console, but could be extended to log to file).
- **Configuration issues**: Ensure your `config.json`, and especially the remote/local `config.yaml`, are valid and correctly formatted. YAML syntax errors can prevent Mihomo from starting.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to open issues or submit pull requests.
