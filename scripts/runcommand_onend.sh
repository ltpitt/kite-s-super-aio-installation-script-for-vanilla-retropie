#!/bin/sh
COMBO_BREAKER="/home/pi/Super-AIO-Setup/scripts/co-co-combo-breaker.py"
COMBO_PID_FILE="/tmp/super-aio-combo-breaker.pid"

if [ -f "$COMBO_PID_FILE" ]; then
    combo_pid=$(cat "$COMBO_PID_FILE")
    case "$combo_pid" in
        ''|*[!0-9]*) ;;
        *)
            if ps -p "$combo_pid" -o args= 2>/dev/null | grep -F -- "$COMBO_BREAKER" >/dev/null 2>&1; then
                kill "$combo_pid" 2>/dev/null || true
            fi
            ;;
    esac
    rm -f "$COMBO_PID_FILE"
fi
