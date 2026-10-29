# Super-AIO Installation for RetroPie 🚀🎮

## Overview

Super-AIO is an **automated setup script** designed for **RetroPie** on a **Raspberry Pi**, streamlining installation, configuration, and optimization for **handheld retro gaming**.

In the early days, handheld retro emulation was a **wild west** of hacked Game Boys, custom Linux builds, and DIY soldering projects. The **Raspberry Pi revolutionized** everything—putting **arcade cabinets, PlayStations, and Nintendo classics in the palms of enthusiasts everywhere**. And at the heart of it all? **RetroPie**, the platform that brought it all together.

We built this project for **the love of hacking**, the thrill of **homebrew**, and the **pure nostalgia** of playing Pokémon on a screen smaller than your palm. This is **for the tinkerers, the creators, and the game lovers**. 🎮

## Features ✨

- **Fully automated setup**  
- **Optimized emulator configurations (PiFBA & MAME4All)**  
- **Known-good standalone `pcsx-rearmed` Arduino controller configuration**
- **One complete, idempotent installer for first runs and maintenance**
- **Pi Zero-friendly emulator checks/installers for `pcsx-rearmed`, PiFBA, and MAME4All**
- **Per-change approval with previews and timestamped rollback snapshots**
- **SSH enablement marker and Super-AIO systemd service**
- **Secret-safe Wi-Fi handling; credentials are never copied automatically**
- **No `xboxdrv` dependency**

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
chmod +x install-saio.sh scripts/*.sh
./install-saio.sh
```

The installer asks for sudo authentication when needed. It checks every prerequisite and active configuration first, skips matching items, and proposes only missing or changed items. It does not reboot the device.

`install-saio.sh` is the only setup entry point. The other files under `scripts/` are runtime hooks, utilities, or targeted repair tools.

---

### Installer modes

The default mode performs the complete setup. It can safely be run again after partial or previous setup:

```bash
./install-saio.sh
```

To inspect the complete ordered plan without sudo authentication or changing anything:

```bash
./install-saio.sh --dry-run
```

The dry run reports skipped checks, proposed file diffs, and the commands that would install packages, copy files, change permissions, update hooks, create the SSH marker, or manage the Super-AIO service. SSH is considered configured when its service is active/enabled, `sshd` is running, or port 22 is listening, so an existing working SSH setup does not trigger a marker change.

The installer also proposes the repository's standalone `pcsx-rearmed` configuration, based on the working Game Boy mapping for the Arduino Leonardo. It keeps the keyboard and Arduino bindings and omits the obsolete `xboxdrv` binding.

To create a backup snapshot without applying changes:

```bash
./install-saio.sh --snapshot-only
```

Each run stores private snapshots, logs, and a change manifest below `backups/install-saio/`. The command to roll back a run is printed at the end:

```bash
./install-saio.sh --rollback "$PWD/backups/install-saio/YYYYMMDD-HHMMSS"
```

Rollback restores files and service state. If the run installed a dependency or cloned Super-AIO, rollback asks before removing it and retains repositories with later changes.

---

## Backup System 🗂️

Before modifying an existing file, the installer displays the difference and saves the original under the run directory. New files are recorded so rollback removes them. Wi-Fi credentials are never included in snapshots or copied automatically.

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

`co-co-combo-breaker.py` is a flexible utility for identifying button codes and monitoring for a configured two-button combo to kill running emulators.

#### How it works
- The installer copies this script to `/home/pi/.local/lib/super-aio/` as the stable runtime location used by RetroPie.
- During setup, it detects the Kite SAIO Arduino Leonardo, selects it by default, and can capture any two gamepad buttons pressed together.
- The selected device name, stable device path when available, and button codes are saved in `/home/pi/.config/super-aio/combo-breaker.conf`.
- For supported emulators (e.g., `mame4all`, `pico8`), `runcommand_onstart.sh` validates the saved mapping and starts one background `python3` monitor as the `pi` user; `runcommand_onend.sh` stops it when the emulator exits.
- When you press the configured two-button combo on your gamepad, the script will kill the emulator process, allowing for a quick exit.
- You can also run it manually for advanced usage or to identify button codes.

#### Usage & Help

```bash
python3 scripts/co-co-combo-breaker.py --configure
```

Running the script without arguments creates the default configuration when it is missing and starts monitoring the configured combo. `--configure` is the only normal setup mode: it selects the gamepad and captures two buttons pressed together. Requires Python 3 and the `evdev` module; the installer installs it when needed.

#### Checking the first-time setup

Run the installer from the checkout on the Raspberry Pi:

```bash
cd ~/kite-s-super-aio-installation-script-for-vanilla-retropie
chmod +x install-saio.sh scripts/*.sh
./install-saio.sh
```

When the combo-breaker prompt appears, answer `y`. If no configuration exists, the installer creates the documented defaults for the Arduino Leonardo (`event4` or its `/dev/input/by-id` path), SELECT `314`, START `315`, and processes `mame pico8`. To choose another HID event node or capture a custom two-button combo, run `--configure`. After setup, verify the saved mapping and runtime copy with:

```bash
python3 /home/pi/.local/lib/super-aio/co-co-combo-breaker.py \
  --check-config \
  --config /home/pi/.config/super-aio/combo-breaker.conf
```

To test the RetroPie hooks without launching a game, start and stop a test monitor as the `pi` user:

```bash
sh /opt/retropie/configs/all/runcommand-onstart.sh test mame4all
cat /tmp/super-aio-combo-breaker.pid
ps -o user,pid,args -p "$(cat /tmp/super-aio-combo-breaker.pid)"
sh /opt/retropie/configs/all/runcommand-onend.sh
```

---

### Device repair scripts

The following scripts make targeted, backed-up changes for known device issues:

```bash
./scripts/fix-asplashscreen-scaling.sh
./scripts/fix-retroarch-controller-index.sh
```

The splash script sets the tested `320x240+0+0` window and the RetroArch script sets player 1 to controller index `0`. Both refuse ambiguous input and keep backups under `backups/`.
