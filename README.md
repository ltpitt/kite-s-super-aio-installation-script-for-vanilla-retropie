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
