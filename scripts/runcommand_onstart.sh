#!/bin/sh
# emu name to /dev/shm/runcommand.log
echo "on-start: $2" >&2

if [ "$2" = "mame4all" ] || [ "$2" = "pico8" ]; then
  COMBO_BREAKER="/home/pi/Super-AIO-Setup/scripts/co-co-combo-breaker.py"
  COMBO_CONFIG="/home/pi/.config/super-aio/combo-breaker.conf"
  COMBO_PID_FILE="/tmp/super-aio-combo-breaker.pid"

  if [ -f "$COMBO_PID_FILE" ]; then
    old_pid=$(cat "$COMBO_PID_FILE")
    case "$old_pid" in
      ''|*[!0-9]*) ;;
      *)
        if ps -p "$old_pid" -o args= 2>/dev/null | grep -F -- "$COMBO_BREAKER" >/dev/null 2>&1; then
          kill "$old_pid" 2>/dev/null || true
        fi
        ;;
    esac
    rm -f "$COMBO_PID_FILE"
  fi

  if [ -f "$COMBO_BREAKER" ] &&
    [ -f "$COMBO_CONFIG" ] &&
    /usr/bin/python3 "$COMBO_BREAKER" --check-config --config "$COMBO_CONFIG" >/dev/null 2>&1; then
    /usr/bin/python3 "$COMBO_BREAKER" --combo --config "$COMBO_CONFIG" &
    echo "$!" > "$COMBO_PID_FILE"
  else
    echo "Combo breaker is not configured for the gamepad; run install-saio.sh." >&2
  fi
fi
