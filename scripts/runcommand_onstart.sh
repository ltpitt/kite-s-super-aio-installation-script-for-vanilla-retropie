#!/bin/sh
# emu name to /dev/shm/runcommand.log
echo "on-start: $2" >&2

if [ "$2" = "pifba" ]; then
  sudo systemctl stop xboxdrv.service
fi

if [ "$2" = "mame4all" ] || [ "$2" = "pico8" ]; then
  /home/pi/Super-AIO-Setup/scripts/co-co-combo-breaker.py --combo &
fi