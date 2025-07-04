# Super-AIO Installation for RetroPie 🚀🎮

## Overview

Super-AIO is an **automated setup script** designed for **RetroPie** on a **Raspberry Pi**, streamlining installation, configuration, and optimization for **handheld retro gaming**.

In the early days, handheld retro emulation was a **wild west** of hacked Game Boys, custom Linux builds, and DIY soldering projects. The **Raspberry Pi revolutionized** everything—putting **arcade cabinets, PlayStations, and Nintendo classics in the palms of enthusiasts everywhere**. And at the heart of it all? **RetroPie**, the platform that brought it all together.

We built this project for **the love of hacking**, the thrill of **homebrew**, and the **pure nostalgia** of playing Pokémon on a screen smaller than your palm. This is **for the tinkerers, the creators, and the game lovers**. 🎮

## Features ✨

- **Fully automated setup**  
- **Optimized emulator configurations (PiFBA & MAME4All)**  
- **Automatic backups with timestamps**  
- **Idempotent execution (safe for multiple runs)**  
- **SSH enabled automatically on first reboot**  
- **Wi-Fi configuration support (`wpa_supplicant.conf`)**  
- **Systemd service for Super-AIO auto-launch**

---

## File Locations 📁

| Component                    | Location                                      |
|-----------------------------|-----------------------------------------------|
| Super-AIO Repository        | `/home/pi/Super-AIO/`                         |
| Configuration Files         | `configs/`                                    |
| Emulator Config (PiFBA)     | `configs/fba2x.cfg`                           |
| Emulator Config (MAME4All)  | `configs/mame.cfg`                            |
| Wi-Fi Setup File            | `/boot/wpa_supplicant.conf`                   |
| Example Wi-Fi Config        | `configs/wpa_supplicant.example.conf`         |
| RetroPie Startup Script     | `/opt/retropie/configs/all/autostart.sh`      |
| All Scripts                 | `scripts/`                                    |

---

## Installation Instructions 🛠️

### Step 1: Download the Scripts

All scripts are now in the `scripts/` folder. For example, to run the installer:

```bash
bash install-saio.sh
```

### Step 2: Make It Executable

```bash
chmod +x install-saio.sh
```

### Step 3: Run the Installation

```bash
bash install-saio.sh
```

---

## Systemd Service for Auto-Startup 🖥️

Super-AIO runs at boot using systemd.

### Manually Start or Stop the Service

Run the following commands:

```bash  
  sudo systemctl start saio.service  
  sudo systemctl stop saio.service
```

### Check the Service Status

Run:

```bash
  sudo systemctl status saio.service
```

### Enable Auto-Start on Boot

Run:

```bash  
  sudo systemctl enable saio.service
```

---

## Backup System 🗂️

Before modifying any file, the script creates timestamped backups (e.g., `config.txt_2025-05-20_22-15-30.backup`).

### How to Restore a Backup

Simply copy the desired backup file over the existing configuration:

```bash  
  sudo cp /boot/config.txt_YYYY-MM-DD_HH-MM-SS.backup /boot/config.txt
```

---

## Utilities 🧰

### ROM Sync Script

`sync-roms-from-usb.sh` helps you quickly copy ROMs from a USB stick to your RetroPie system, preserving folder structure and only copying supported file types.

#### Usage & Help

```bash
bash scripts/sync-roms-from-usb.sh --help
```

> Run the script with `--help` to see all available options and usage examples. The script supports overriding source, destination, and file extensions at runtime.

---

### Co-Co-Combo Breaker

`co-co-combo-breaker.py` is a flexible utility for identifying button codes and monitoring for Select+Start combos to kill running emulators.

#### Usage & Help

```bash
python3 scripts/co-co-combo-breaker.py --help
```

> Run the script with `--help` to see all available options and usage examples. Requires Python 3 and the `evdev` module (`sudo pip3 install evdev`).

---

## Script Permissions

The installer (`install-saio.sh`) sets executable permissions for all scripts in the `scripts/` folder. If you add new scripts, you may need to run:

```bash
chmod +x scripts/your-script.sh
```

---

## .gitignore

A sensible `.gitignore` is included to exclude Python cache, editor files, macOS files, backup/log files, and other common clutter.
