#!/bin/bash

# Define source and destination base directories
SRC_BASE="/media/usb1/home/pi/RetroPie/roms"
DEST_BASE="/home/pi/RetroPie/roms"

# List of common ROM file extensions
INCLUDE_EXTENSIONS=("nes" "snes" "gba" "gb" "gbc" "md" "sms" "gg" "pce" "tg16" "zip")

# Iterate over all directories in the source base directory
for dir in "$SRC_BASE"/*/; do
    # Extract the folder name
    folder_name=$(basename "$dir")

    # Ensure the destination directory exists
    mkdir -p "$DEST_BASE/$folder_name"

    # Sync only the files with the specified extensions
    for ext in "${INCLUDE_EXTENSIONS[@]}"; do
        rsync -av --include="*.${ext}" --exclude="*" "$dir" "$DEST_BASE/$folder_name/"
    done
done

echo "ROM sync completed!"

