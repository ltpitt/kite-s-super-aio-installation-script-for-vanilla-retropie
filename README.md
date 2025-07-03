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

### Step 1: Download the Script  
Save `setup.sh` to your Raspberry Pi in the **home directory** (`/home/pi/`).  

### Step 2: Make It Executable  
Run the following command:  
```bash
chmod +x setup.sh
```

Step 3: Run the Installation
Run the script:
```bash
bash setup.sh
```

🚀 The system will reboot automatically after setup.

File Locations 📁
Component	Location
Super-AIO Repository	/home/pi/Super-AIO/
Configuration Files	/boot/
Emulator Config (PiFBA)	/opt/retropie/configs/fba/
Emulator Config (MAME4All)	/opt/retropie/configs/mame-mame4all/
Wi-Fi Setup File	/boot/wpa_supplicant.conf
RetroPie Startup Script	/opt/retropie/configs/all/autostart.sh
RetroPie Runcommand Hooks	/opt/retropie/configs/all/runcommand-onstart.sh & /opt/retropie/configs/all/runcommand-onend.sh
Systemd Service for Auto-Startup 🖥️
Super-AIO runs at boot using systemd.

Manually Start or Stop the Service
Run the following commands:

bash
sudo systemctl start saio.service
sudo systemctl stop saio.service
Check the Service Status
Run:

bash
sudo systemctl status saio.service
Enable Auto-Start on Boot
Run:

bash
sudo systemctl enable saio.service
Backup System 🗂️
Before modifying any file, the script creates timestamped backups (e.g., config.txt_2025-05-20_22-15-30.backup).

How to Restore a Backup
Simply copy the desired backup file over the existing configuration:

bash
sudo cp /boot/config.txt_YYYY-MM-DD_HH-MM-SS.backup /boot/config.txt

Links & Community 🔗
Super-AIO Project by Kite → GitHub

RetroPie Official Website → RetroPie.org.uk

Raspberry Pi Foundation → RaspberryPi.org

A Love Letter to RetroPie ❤️
To the developers, the modders, and the dreamers behind RetroPie—thank you. You took a tiny piece of silicon, gave it a heartbeat, and built the greatest DIY retro gaming platform of all time.

From the early days of RetroPie 1.0, to today’s multi-platform, shader-packed, joystick-tuned perfection, your dedication has kept the spirit of classic gaming alive. We hope this script helps more people experience the magic of RetroPie—whether they’re booting up their first Pi or tweaking their hundredth config file at 2AM.

Here's to arcade legends, homebrew pioneers, and every Game Boy-loving hacker who ever pressed SELECT + START to quit.

🎮 Long live RetroPie.
