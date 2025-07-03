#!/bin/bash
# ============================================================
# Super-AIO Installation Script for RetroPie (Raspberry Pi)
# ============================================================
#
# This script automates the installation and setup of the
# Super-AIO project on a Raspberry Pi running RetroPie.
# Be sure to run it BEFORE configuring any gamepad.
#
# Features:
# - Installs dependencies **only if missing**.
# - Copies key emulator configurations for **PiFBA** and **MAME4All**.
# - Configures a systemd service **safely** without duplication.
# - **Backs up every modified file with a timestamp**.
# - **Enables SSH automatically** on first reboot.
# - **Copies Wi-Fi configuration** (`wpa_supplicant.conf`) if present.
# - **Supports restoring previous backups by timestamp**.
#
# ============================================================

# ==== PATH CONSTANTS ====
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# System paths
REPO_PATH="/home/pi/Super-AIO"
SETUP_PATH="/home/pi/Super-AIO-Setup"
CONFIG_PATH="/opt/retropie/configs/all"
FBA_PATH="/opt/retropie/configs/fba"
MAME_PATH="/opt/retropie/configs/mame-mame4all"
BOOT_PATH="/boot"

# Important files
AUTOSTART_FILE="$CONFIG_PATH/autostart.sh"
RUNCOMMAND_START="$CONFIG_PATH/runcommand-onstart.sh"
RUNCOMMAND_END="$CONFIG_PATH/runcommand-onend.sh"
SYSTEMD_SERVICE="/etc/systemd/system/saio.service"
XBOXDRV_SERVICE="/etc/systemd/system/xboxdrv.service"

# ==== RESTORE MODE ====
if [[ "$1" == "restore" ]]; then
    RESTORE_TIMESTAMP="$2"
    if [ -z "$RESTORE_TIMESTAMP" ]; then
        echo "Available backup timestamps:"
        find /etc /boot /opt/retropie/configs -type f -name "*.backup" 2>/dev/null | sed 's/.*_//;s/.backup//' | sort -u
        echo "Usage: $0 restore <timestamp>"
        exit 0
    fi

    echo "Restoring backups with timestamp: $RESTORE_TIMESTAMP"

    restore_file() {
        local original="$1"
        local backup="${original}_${RESTORE_TIMESTAMP}.backup"
        if [ -f "$backup" ]; then
            echo "Restoring $original from $backup"
            sudo cp "$backup" "$original"
        else
            echo "No backup found for $original with timestamp $RESTORE_TIMESTAMP"
        fi
    }

    restore_file "/etc/asound.conf"
    restore_file "$BOOT_PATH/config.txt"
    restore_file "$BOOT_PATH/config-saio.txt"
    restore_file "$AUTOSTART_FILE"
    restore_file "$FBA_PATH/fba2x.cfg"
    restore_file "$MAME_PATH/mame.cfg"
    restore_file "$RUNCOMMAND_START"
    restore_file "$RUNCOMMAND_END"
    restore_file "$BOOT_PATH/wpa_supplicant.conf"

    echo "Restore complete. A reboot is recommended."
    exit 0
fi

# ==== BACKUP FUNCTION ====
backup_file() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        sudo cp "$file_path" "${file_path}_${TIMESTAMP}.backup"
        echo "Backup created for $file_path"
    fi
}

echo "Updating system package list..."
sudo apt-get update -y

echo "Checking and installing required dependencies..."
PKGS=("libpng12-0")
for pkg in "${PKGS[@]}"; do
    if ! dpkg -l | grep -q "$pkg"; then
        echo "Installing missing package: $pkg"
        sudo apt-get install "$pkg" -y
    else
        echo "Package $pkg is already installed, skipping."
    fi
done

echo "Cloning Super-AIO repository..."
if [ ! -d "$REPO_PATH" ]; then
    git clone https://github.com/geebles/Super-AIO/ "$REPO_PATH"
else
    echo "Super-AIO repository already exists, skipping clone."
fi
cd "$REPO_PATH/release/saio"

echo "Installing Python serial package..."
if ! dpkg -l | grep -q "python-serial"; then
    sudo dpkg -i python-serial_2.6-1.1_all.deb
else
    echo "Python serial package is already installed, skipping."
fi

echo "Setting executable permissions..."
FILES=(
    "../tester/pngview"
    "osd/saio-osd"
    "rfkill/rfkill"
    "flash/flash.sh"
)
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        sudo chmod +x "$file"
    fi
done

echo "Backing up configuration files before modification..."
backup_file "/etc/asound.conf"
backup_file "$BOOT_PATH/config.txt"
backup_file "$BOOT_PATH/config-saio.txt"

echo "Copying essential configuration files..."
sudo cp -u asound.conf /etc/
sudo cp -u config.txt "$BOOT_PATH/config.txt"
sudo cp -u config-saio.txt "$BOOT_PATH/config-saio.txt"

echo "Backing up and updating RetroPie autostart script..."
backup_file "$AUTOSTART_FILE"
sudo cp -u autostart.sh "$AUTOSTART_FILE"

echo "Setting up sound configuration..."
if [ ! -f "/home/pi/.asoundrc" ]; then
    echo -e "pcm.!default {
	type hw
	card 1
}

ctl.!default {
	type hw
	card 1
}" | sudo tee /home/pi/.asoundrc
fi

echo "Backing up and copying emulator configuration files..."
backup_file "$FBA_PATH/fba2x.cfg"
backup_file "$MAME_PATH/mame.cfg"
sudo cp -u "$SETUP_PATH/fba2x.cfg" "$FBA_PATH/"
sudo cp -u "$SETUP_PATH/mame.cfg" "$MAME_PATH/"

echo "Enabling SSH on first reboot..."
if [ ! -f "$BOOT_PATH/ssh" ]; then
    sudo touch "$BOOT_PATH/ssh"
fi

echo "Checking for Wi-Fi configuration..."
if [ -f "$SETUP_PATH/wpa_supplicant.conf" ]; then
    backup_file "$BOOT_PATH/wpa_supplicant.conf"
    sudo cp -u "$SETUP_PATH/wpa_supplicant.conf" "$BOOT_PATH/"
fi

echo "Backing up existing runcommand scripts..."
backup_file "$RUNCOMMAND_START"
backup_file "$RUNCOMMAND_END"

echo "Copying new runcommand scripts..."
sudo cp -u "$SETUP_PATH/runcommand-onstart.sh" "$RUNCOMMAND_START"
sudo cp -u "$SETUP_PATH/runcommand-onend.sh" "$RUNCOMMAND_END"

echo "Creating systemd service for Super-AIO..."
if [ ! -f "$SYSTEMD_SERVICE" ]; then
    sudo tee "$SYSTEMD_SERVICE" > /dev/null <<EOF
[Unit]
Description=Super-AIO Service
After=network.target

[Service]
ExecStart=/usr/bin/nice -n 19 /usr/bin/python3 $REPO_PATH/release/saio/saio-osd.py
Restart=always
User=pi
WorkingDirectory=$REPO_PATH/release/saio/
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=saio-service
Nice=19

[Install]
WantedBy=multi-user.target
EOF
else
    echo "Service file already exists, skipping creation."
fi

echo "Creating systemd service for xboxdrv..."
if [ ! -f "$XBOXDRV_SERVICE" ]; then
    sudo tee "$XBOXDRV_SERVICE" > /dev/null <<EOF
[Unit]
Description=Start xboxdrv at boot
After=network.target

[Service]
ExecStart=/opt/retropie/supplementary/xboxdrv/bin/xboxdrv \
    --evdev /dev/input/by-id/usb-Arduino_LLC_Arduino_Leonardo_HIDAF-if02-event-joystick \
    --silent \
    --detach-kernel-driver \
    --force-feedback \
    --deadzone-trigger 15% \
    --deadzone 4000 \
    --mimic-xpad \
    --device-name "XBOX 360 Controller (xboxdrv)" \
    --evdev-absmap ABS_HAT0X=dpad_x,ABS_HAT0Y=dpad_y \
    --evdev-keymap BTN_THUMB2=x,BTN_THUMB=a,BTN_TRIGGER=b,BTN_PINKIE=back,BTN_BASE=lb,BTN_BASE3=rb,BTN_TOP=y,BTN_TOP2=start \
    --dpad-only \
    --ui-axismap lt=void,rt=void \
    --ui-buttonmap tl=void,tr=void,guide=void
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF
else
    echo "xboxdrv service already exists, skipping creation."
fi

echo "Reloading systemd and enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable saio.service
sudo systemctl start saio.service
sudo systemctl enable xboxdrv
sudo systemctl start xboxdrv

echo "Checking Super-AIO service status..."
sudo systemctl status saio.service

echo "Checking xboxdrv service status..."
sudo systemctl status xboxdrv

echo "Rebooting system..."
sudo reboot
