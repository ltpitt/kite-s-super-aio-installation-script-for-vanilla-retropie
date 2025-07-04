#!/bin/bash
# Default parameters
SRC_BASE="/media/usb1/home/pi/RetroPie/roms"
DEST_BASE="/home/pi/RetroPie/roms"
INCLUDE_EXTENSIONS=("nes" "snes" "gba" "gb" "gbc" "md" "sms" "gg" "pce" "tg16" "zip")

show_help() {
  echo "sync-roms-from-usb.sh: Sync ROM files from a USB drive to your RetroPie system."
  echo
  echo "Copies ROM files from a source directory (e.g. USB stick) to your RetroPie ROMs folder,"
  echo "preserving subfolders and only copying files with specified extensions."
  echo
  echo "Usage: $0 [--src DIR] [--dest DIR] [--ext EXT1,EXT2,...]"
  echo
  echo "Options:"
  echo "  --src DIR      Source ROMs directory (default: $SRC_BASE)"
  echo "  --dest DIR     Destination ROMs directory (default: $DEST_BASE)"
  echo "  --ext LIST     Comma-separated list of file extensions (default: ${INCLUDE_EXTENSIONS[*]})"
  echo "  -h, --help     Show this help message and exit"
  echo
  echo "Example:"
  echo "  $0 --src /media/usb0/roms --dest /home/pi/RetroPie/roms --ext zip,nes,sfc"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)
      SRC_BASE="$2"; shift 2;;
    --dest)
      DEST_BASE="$2"; shift 2;;
    --ext)
      IFS=',' read -ra INCLUDE_EXTENSIONS <<< "$2"; shift 2;;
    -h|--help)
      show_help; exit 0;;
    *)
      echo "Unknown option: $1"; show_help; exit 1;;
  esac
done

echo "Source directory:      $SRC_BASE"
echo "Destination directory: $DEST_BASE"
echo "Extensions:            ${INCLUDE_EXTENSIONS[*]}"
echo
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
