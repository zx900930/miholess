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
  - **Windows:** Utilizes PowerShell, [NSSM (Non-Sucking Service Manager)](https://nssm.cc/) for robust Windows Services, and `schtasks.exe` for periodic updates.
  - **Linux:** Uses Bash scripts, systemd for service management and timers for periodic updates.
- **Customizable Sources:** Allows users to specify custom mirror URLs for Mihomo binaries and data files, as well as a custom remote configuration URL.
- **Flexible Configuration Management:** Use a single remote URL for your main configuration, or manage your `config.yaml` entirely locally.

## Project Structure

```
miholess/
├── README.md
├── LICENSE
├── config.example.json         # Example configuration file
├── Windows/
│   ├── install.ps1             # Main interactive installation script
│   ├── uninstall.ps1           # Uninstallation script
│   ├── miholess_core_updater.ps1  # Script to update Mihomo core
│   ├── miholess_config_updater.ps1 # Script to update remote configurations
│   ├── miholess.ps1            # Mihomo setup script (run by scheduled tasks)
│   ├── helper_functions.ps1    # Common PowerShell functions
│   └── nssm/                   # Directory containing bundled NSSM executable
│       └── nssm.exe
├── Linux/
│   ├── install.sh              # Main installation script
│   ├── uninstall.sh            # Uninstallation script
│   ├── miholess_core_updater.sh   # Script to update Mihomo core
│   ├── miholess_config_updater.sh # Script to update remote configurations
│   ├── miholess.service        # systemd service unit file
│   └── helper_functions.sh     # Common Bash functions
```

## Installation

### Prerequisites

- **Windows:**
  - Windows 7 SP1 or later, Windows Server 2008 R2 SP1 or later.
  - PowerShell 5.1 or newer (PowerShell 7+ is recommended for best compatibility and features).
  - **Administrator privileges** are required for installation and uninstallation.
  - An active internet connection to download Mihomo and related files.
- **Linux:**
  - A systemd-based Linux distribution (e.g., Ubuntu, Debian, Fedora, CentOS 7+).
  - `bash`, `curl`, `jq`, `tar`, `gzip`, `unzip` utilities. The installer will attempt to install missing dependencies.
  - **Root privileges** (or `sudo`) are required for installation and uninstallation.
  - An active internet connection.

### Windows Installation

The installation process is interactive and guided by the script. The following simple one-liner initiates the process by downloading and executing the main installer script.

**Important:** For NSSM to be available, you **must ensure a compatible `nssm.exe` (preferably the `win64` version) is placed in `miholess/Windows/nssm/` in your repository** before running the installation command.

**Recommended (Simple One-liner for fresh install):**

Open **PowerShell as Administrator** and run the following command. The script will then prompt you for configuration details:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; irm https://raw.githubusercontent.com/zx900930/miholess/main/Windows/install.ps1 | iex
```

**Explanation of the one-liner:**

- `Set-ExecutionPolicy Bypass -Scope Process -Force`: This temporarily sets the PowerShell execution policy to `Bypass` for the current PowerShell session (process), allowing the script to run without security prompts. The `-Force` parameter suppresses the confirmation message.
- `[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072`: This explicitly enables TLS 1.2 (value 3072) for web requests within the current session. This helps prevent issues when downloading files from HTTPS URLs, especially on older Windows versions.
- `irm https://raw.githubusercontent.com/zx900930/miholess/main/Windows/install.ps1 | iex`: This downloads the `install.ps1` script content directly from GitHub using `Invoke-RestMethod` (`irm`) and immediately executes it using `Invoke-Expression` (`iex`). The `install.ps1` script then handles downloading all other necessary components (like `helper_functions.ps1`) from your repository and copies NSSM from its bundled location.

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

1.  Copy NSSM and all necessary Miholess PowerShell scripts to the installation directory.
2.  Download the latest Mihomo core and required data files.
3.  Create a `config.json` file in the installation directory based on your input.
4.  Set up a Windows Service named `MiholessService` using NSSM to ensure Mihomo runs automatically on system startup and restarts if it crashes.
5.  Create two Scheduled Tasks using `schtasks.exe`:
    - `Miholess_Core_Updater`: Runs daily at 3:00 AM to check for and update the Mihomo core.
    - `Miholess_Config_Updater`: Runs hourly to check for and update the remote configuration.

### Linux Installation

The `install.sh` script is an interactive installer that guides you through the setup.

**Recommended (One-liner for fresh install):**

Open a **terminal as root** (or use `sudo -i` then paste the command) and run:

```bash
curl -sL https://raw.githubusercontent.com/zx900930/miholess/main/Linux/install.sh | bash
```

**Explanation of the one-liner:**

- `curl -sL ...`: Downloads the `install.sh` script content silently (`-s`) and follows redirects (`-L`).
- `| bash`: Pipes the downloaded script content directly to `bash` for execution.

**Interactive Setup Steps:**

Once the script starts, it will prompt you for the following information. Default values are provided in parentheses; press Enter to accept the default or type a new value.

- **Installation Directory:** Where Miholess and Mihomo files will be stored (e.g., `/opt/miholess`).
- **Mihomo Core Download Mirror URL:** Base URL for Mihomo binary downloads. Use this for GitHub mirrors.
- **GeoIP.dat download URL**
- **GeoSite.dat download URL**
- **Country.mmdb download URL**
- **Remote configuration URL:** The URL of your main Mihomo configuration file. Leave empty if you manage `config.yaml` locally.
- **Local configuration folder path:** A folder where Mihomo's `config.yaml` (and potentially other data files) will reside (e.g., `/etc/mihomo`).
- **Mihomo listen port:** The port Mihomo will listen on (default: `7890`).
- **Force re-installation:** Choose Y/N if you want to overwrite an existing Miholess installation.

After you provide all details, a summary will be displayed, and you'll be asked to press Enter to confirm and proceed.

After installation, `miholess` will:

1.  Check for and attempt to install required dependencies (`curl`, `jq`, `tar`, `gzip`, `unzip`).
2.  Create necessary directories.
3.  Create a `config.json` file in the installation directory based on your input.
4.  Download the latest Mihomo core and required data files.
5.  Copy helper scripts to the installation directory.
6.  Set up a `systemd` service (`miholess.service`) to run `mihomo` directly, ensuring it starts automatically on boot and restarts if it crashes.
7.  Create `systemd` timers:
    - `miholess-core-updater.timer`: Runs `miholess_core_updater.sh` daily to update the Mihomo core.
    - `miholess-config-updater.timer`: Runs `miholess_config_updater.sh` hourly to update the configuration and geodata.

### Linux Uninstallation

To uninstall `miholess`, open a **terminal as root** (or use `sudo`) and run:

```bash
curl -sL https://raw.githubusercontent.com/zx900930/miholess/main/Linux/uninstall.sh | bash
```

This script will stop and disable systemd services and timers, remove their unit files, and delete the Miholess installation directory.

### Linux Usage and Troubleshooting

- **Service Status:** `systemctl status miholess.service`
- **Start/Stop Service:** `sudo systemctl start miholess.service` / `sudo systemctl stop miholess.service`
- **Timer Status:** `systemctl list-timers miholess-*`
- **Mihomo Logs:** Check the file path specified in `config.json` (default: `/opt/miholess/mihomo.log`).
- **Miholess Script Logs:** Check `/opt/miholess/miholess_service.log` for logs from the Miholess update scripts.
- **Firewall:** Ensure Mihomo's listen port (default 7890) is allowed through your system's firewall (e.g., `ufw allow 7890/tcp` if using UFW).
- **Permissions:** Ensure Mihomo can read/write to its configured directories (`/etc/mihomo` or your chosen local config path). If running as a non-root user, adjust permissions accordingly.

## Configuration

All core settings for `miholess` are stored in a `config.json` file located in your `installation_dir` (default: `C:\ProgramData\miholess\config.json`).

You can view an example structure in `config.example.json` at the root of this repository.

**To modify the configuration AFTER installation:**

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

Open PowerShell and run:

```powershell
schtasks.exe /query /TN Miholess_* /FO LIST
```

### Checking Mihomo Logs

You can find Mihomo's logs at the path specified in your `config.json` (default: `C:\ProgramData\miholess\mihomo.log`).

## Uninstallation

### Windows Uninstallation

To uninstall `miholess`, open **PowerShell as Administrator** and run the following command:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; irm https://raw.githubusercontent.com/zx900930/miholess/main/Windows/uninstall.ps1 | iex
```

This script will stop and remove the Windows Service (using NSSM), unregister the scheduled tasks (using `schtasks.exe`), and delete the Miholess installation directory.

### Linux Uninstallation (Planned)

_(This section will be filled once the Linux scripts are developed)_

## Troubleshooting

- **Installation Failure / Script Quits Without Logs**: If the installation one-liner fails immediately or provides no output, double-check that you are running PowerShell as Administrator and have a stable internet connection.
- **"Security policy stopped it from running" or parsing errors**: Ensure you are using the exact one-liner provided in the "Recommended (Simple One-liner for fresh install)" section.
- **"Script must be run with Administrator privileges"**: Ensure you open PowerShell by right-clicking its icon and selecting "Run as administrator".
- **NSSM not found**: Ensure `nssm.exe` is correctly placed in the `Windows/nssm/` folder within your repository and committed. The installer will copy it from there.
- **Mihomo not running / Service restarting**:
  - Check `Get-Service MiholessService` status. If stopped, try `Start-Service MiholessService`.
  - Crucially, check `C:\ProgramData\miholess\mihomo.log` for direct errors from Mihomo itself.
  - Ensure no other application is using Mihomo's configured port (`mihomo_port`).
  - Verify that a valid `config.yaml` exists in your `local_config_path` directory.
- **Updates not happening**:
  - Check scheduled task status using `schtasks.exe /query /TN Miholess_* /FO LIST`.
  - Manually trigger the updater scripts from the installation directory (e.g., `C:\ProgramData\miholess\miholess_core_updater.ps1`).
  - Check the logs for these scripts (they output to console, but could be extended to log to file).
- **Configuration issues**: Ensure your `config.json`, and especially the remote/local `config.yaml`, are valid and correctly formatted. YAML syntax errors can prevent Mihomo from starting.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to open issues or submit pull requests.
