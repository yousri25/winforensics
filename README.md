# winforensics

Run Windows-only forensics tools (Eric Zimmerman's Registry Explorer, Timeline Explorer, etc.) on Linux with **one command**.

`winforensics` starts a Windows 11 VM in Docker, opens it in a normal resizable RDP window, and **shuts the VM down when you close the window**.

```
winforensics   →   docker (dockur/windows, KVM)   →   RDP window   →   close = VM stops
```

## Why not Wine?

Zimmerman's GUI tools are WPF/WinForms apps built with DevExpress. Under Wine they tend to crash on font enumeration or draw black popup windows, especially on Wayland. A real Windows VM runs them exactly as on Windows. The command-line tools (MFTECmd, RECmd, EvtxECmd...) do run natively on Linux with .NET, so you only need this for the GUIs.

> **Status:** developed on Omarchy (Arch Linux, Hyprland), where the manual setup behind this project was tested. The installer and launcher scripts are new, and other distros are untested. Issues and PRs welcome.

## Requirements

- Linux with KVM (`/dev/kvm` must exist; enable VT-x / AMD-V in BIOS)
- Docker with the compose plugin
- FreeRDP **3.x** (provides `xfreerdp3`)
- ~8 GB free RAM for the VM, ~64 GB free disk
- Optional: `libnotify` for desktop notifications
- A Windows 11 ISO of your own (recommended), or let the container download one. You are responsible for Windows licensing.

## Install

```bash
git clone https://github.com/yousri25/winforensics.git
cd winforensics
./install.sh
```

The installer checks dependencies (and installs them with `pacman` on Arch), creates `~/.config/winforensics/`, generates a random Windows password, installs the launcher to `~/.local/bin/winforensics` and adds a menu entry. Use `./install.sh --yes` to accept all defaults.

If it adds you to the `docker` group, log out and back in before the first run.

## First run

```bash
winforensics doctor    # verify your setup
winforensics           # first run: installs Windows (20-40 minutes)
```

The launcher waits until Windows answers on RDP, then connects automatically. Watch the install at <http://127.0.0.1:8006>, and close that tab once Windows is installed. Windows allows one session per user, so if the browser session is still signed in, RDP shows an "another user is signed in" prompt: click Yes, or sign out in the browser first.

## Install the tools inside Windows

Once you're connected over RDP, a fresh Windows has none of the tools. Set it up once:

1. Open Edge and install the **.NET Desktop Runtime (x64)** for the version your tools need. Newer Zimmerman builds target .NET 10. It must be the *Desktop* Runtime, not the SDK or the plain runtime.
2. Download the tools from <https://ericzimmerman.github.io> and extract them to `C:\Tools`.
3. Optional: add a Windows Defender exclusion for `C:\Tools`. Forensic tools often trigger it and it slows first launches.

   ```powershell
   Add-MpPreference -ExclusionPath "C:\Tools"
   ```

Your Linux shared folder is available inside Windows at `\\host.lan\Data` if you'd rather copy tools in from Linux.

## Daily use

| Command | What it does |
|---|---|
| `winforensics` | Start the VM, open RDP, stop the VM when the window closes |
| `winforensics stop` | Stop the VM |
| `winforensics status` | Show whether the VM is running |
| `winforensics doctor` | Check dependencies and config |

Or launch **Windows Forensics** from your app menu.

Stopping gives Windows up to 2 minutes for a clean shutdown. Save your work in the VM before closing the window.

## Moving files in and out

`~/WinForensics-Share` (configurable) appears inside Windows as `\\host.lan\Data`. For evidence, copy files into a local folder in the VM (for example `C:\Cases`) rather than opening them over the share. It's faster and keeps the VM from touching your original files.

## Configuration

Edit `~/.config/winforensics/config.env` (see [`config/config.env.example`](config/config.env.example)).

| Variable | Default | Meaning |
|---|---|---|
| `WF_USERNAME` / `WF_PASSWORD` | generated | Windows account. **Only applied at first install.** |
| `WF_RAM`, `WF_CPUS`, `WF_DISK` | 8G, 4, 64G | VM resources |
| `WF_SHARE` | `~/WinForensics-Share` | Folder shared with the VM |
| `WF_STOP_ON_EXIT` | `true` | Stop the VM when the RDP window closes |
| `WF_BOOT_DELAY` | `20` | Seconds to wait after Windows starts answering on RDP |
| `WF_BOOT_TIMEOUT` | `5400` | Give up (and stop the VM) if Windows has not answered on RDP after this many seconds |
| `WF_RDP_FLAGS` | `-gfx /gdi:sw` | Extra FreeRDP flags |

### Using your own Windows ISO

Choose it during `./install.sh`, or create `~/.config/winforensics/compose.iso.yaml` before the first run:

```yaml
services:
  windows:
    volumes:
      - /path/to/Windows11.iso:/boot.iso
```

Use an unmodified x64 Windows 10/11 ISO. Heavily trimmed ISOs can break the automatic install. Home editions don't support RDP hosting, so use Pro, Enterprise or Education.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `/dev/kvm` missing | Enable virtualization in BIOS/UEFI |
| `cannot talk to Docker` | `sudo systemctl enable --now docker`, add yourself to the `docker` group, log out and in |
| Black window after connecting | Keep `WF_RDP_FLAGS=-gfx /gdi:sw` (the default). Also check that the browser tab at :8006 is signed out |
| "Another user is signed in" | Click Yes. To avoid it, sign out of the browser session and don't leave :8006 open |
| Logon failure (`ERRCONNECT_LOGON_FAILURE`) | Username or password in `config.env` doesn't match the Windows account. Remember changing them later doesn't change Windows |
| `xfreerdp3: command not found` | Install FreeRDP 3 (`freerdp` on Arch). FreeRDP 2 is too old |
| Tool says it needs .NET | Install the **Desktop Runtime** (not the SDK or plain runtime) for the major version the tool asks for |
| Slow VM on btrfs | Docker warns about btrfs; consider disabling copy-on-write on the Docker volume directory |
| Something else | `docker logs WinForensics` and `~/.local/state/winforensics/rdp.log` |

## Security notes

- The VM's ports are bound to `127.0.0.1` only.
- The password sits in plain text in `config.env` (mode 600) and is passed to FreeRDP on the command line, so it is visible in the process list to other local users. This is acceptable on a single-user machine for a local-only VM, but do **not** reuse a password you use elsewhere.
- The shared folder is read-write from the VM. Share a dedicated folder, not your whole home directory.
- This is a convenience setup for **analyzing artifacts**, not a hardened malware sandbox. Don't execute untrusted samples in it.

## Uninstall

```bash
./uninstall.sh
```

It removes the launcher and menu entry, and asks before deleting the VM disk and config.

## Credits

- [dockur/windows](https://github.com/dockur/windows) for the Windows-in-Docker image
- [WinApps](https://github.com/winapps-org/winapps) for the idea of integrating a Docker Windows VM with Linux
- [Eric Zimmerman's tools](https://ericzimmerman.github.io/) (not included, downloaded separately)

## License

MIT. See [LICENSE](LICENSE).
