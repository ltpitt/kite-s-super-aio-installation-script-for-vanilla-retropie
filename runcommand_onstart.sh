#!/bin/sh
# emu name to /dev/shm/runcommand.log
echo "on-start: $2" >&2
if [ "$2" = "pifba" ]
then
  sudo systemctl stop xboxdrv.service
fi
