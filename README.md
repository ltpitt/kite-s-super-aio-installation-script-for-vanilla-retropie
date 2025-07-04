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

## Installation Instructions 🛠️

### Step 1: Clone the Repository

Clone this repository to your Raspberry Pi:

```bash
git clone https://github.com/ltpitt/kite-s-super-aio-installation-script-for-vanilla-retropie.git
cd kite-s-super-aio-installation-script-for-vanilla-retropie
```

### Step 2: Run the Installer

Make the installer executable and run it:

```bash
chmod +x install-saio.sh
sudo ./install-saio.sh
```

> The installer will set executable permissions for all scripts in the `scripts/` folder automatically.

---

## Backup System 🗂️

Before modifying any file, the script creates timestamped backups (e.g., `config.txt_2025-05-20_22-15-30.backup`).

### How to Restore a Backup

To list available backup timestamps:

```bash
sudo ./install-saio.sh restore
```

To restore all configuration files from a specific backup timestamp:

```bash
sudo ./install-saio.sh restore YYYY-MM-DD_HH-MM-SS
```

> The script will restore all files backed up at that timestamp. A reboot is recommended after restoring.

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

#### How it works
- The installer places this script in the `scripts/` folder and ensures it is executable.
- It is automatically run in the background by the system for supported emulators (e.g., mame4all, pico8) via the `runcommand_onstart.sh` script.
- When you press Select+Start on your gamepad, the script will kill the emulator process, allowing for a quick exit.
- You can also run it manually for advanced usage or to identify button codes.

#### Usage & Help

```bash
python3 scripts/co-co-combo-breaker.py --help
```

> Run the script with `--help` to see all available options and usage examples. Requires Python 3 and the `evdev` module (`sudo pip3 install evdev`).

---
