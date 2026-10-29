#!/bin/sh
# emu name to /dev/shm/runcommand.log
echo "on-start: $2" >&2

run_as_pi() {
  if [ "$(id -un)" = "pi" ]; then
    /usr/bin/python3 "$@"
  else
    /usr/sbin/runuser -u pi -- /usr/bin/python3 "$@"
  fi
}

run_monitor_as_pi() {
  if [ "$(id -un)" = "pi" ]; then
    exec /usr/bin/python3 "$@"
  else
    exec /usr/sbin/runuser -u pi -- /usr/bin/python3 "$@"
  fi
}

is_pico8_launch=0
case "$1:$2:$3" in
  *"/roms/pico8/"*) is_pico8_launch=1 ;;
esac

if [ "$2" = "mame4all" ] || [ "$2" = "pico8" ] || [ "$1" = "pico8" ] || [ "$is_pico8_launch" -eq 1 ]; then
  COMBO_BREAKER="/home/pi/.local/lib/super-aio/co-co-combo-breaker.py"
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
    run_as_pi "$COMBO_BREAKER" --check-config --config "$COMBO_CONFIG" >/dev/null 2>&1; then
    run_monitor_as_pi "$COMBO_BREAKER" --config "$COMBO_CONFIG" &
    echo "$!" > "$COMBO_PID_FILE"
  else
    echo "Combo breaker is not configured for the gamepad; run install-saio.sh." >&2
  fi
fi
