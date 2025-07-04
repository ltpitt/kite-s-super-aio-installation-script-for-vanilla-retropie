#!/usr/bin/python3
import argparse
import sys
from evdev import InputDevice, ecodes, list_devices
import subprocess


def list_input_devices():
    devices = list_devices()
    if not devices:
        print("No input devices found.")
        return
    print("Available input devices:")
    for path in devices:
        try:
            dev = InputDevice(path)
            print(f"  {path}: {dev.name}")
        except Exception as e:
            print(f"  {path}: <error: {e}>")


def identify_buttons(device_path):
    try:
        device = InputDevice(device_path)
        print(f"Listening on {device.path} ({device.name})")
        print("Press buttons to see their codes. Press Ctrl+C to exit.")
        for event in device.read_loop():
            if event.type == ecodes.EV_KEY:
                print(f"Key event: code={event.code}, value={event.value}")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


def monitor_combo(device_path, select_code, start_code, kill_procs):
    try:
        device = InputDevice(device_path)
        print(f"Monitoring for Select+Start combo on {device.path} ({device.name})...")
        select_pressed = False
        start_pressed = False
        for event in device.read_loop():
            if event.type == ecodes.EV_KEY:
                if event.code == select_code:
                    select_pressed = event.value == 1
                elif event.code == start_code:
                    start_pressed = event.value == 1
                if select_pressed and start_pressed:
                    print(f"Select+Start detected! Killing: {', '.join(kill_procs)}")
                    for proc in kill_procs:
                        subprocess.call(["killall", "-9", proc])
                    break
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Co-Co-Combo Breaker: Identify button codes or monitor for Select+Start combo to kill emulators.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument('--device', '-d', default='/dev/input/event1', help='Input device path (use --list-devices to see all)')
    parser.add_argument('--identify', action='store_true', help='Identify button codes (prints all key events)')
    parser.add_argument('--combo', action='store_true', help='Monitor for Select+Start combo and kill processes')
    parser.add_argument('--select-code', type=int, default=314, help='Button code for SELECT')
    parser.add_argument('--start-code', type=int, default=315, help='Button code for START')
    parser.add_argument('--kill', nargs='+', default=['mame', 'pico8'], help='Process names to kill on combo')
    parser.add_argument('--list-devices', action='store_true', help='List available input devices and exit')
    args = parser.parse_args()

    if args.list_devices:
        list_input_devices()
        sys.exit(0)
    if not (args.identify or args.combo):
        parser.print_help()
        sys.exit(0)
    if args.identify:
        identify_buttons(args.device)
    elif args.combo:
        monitor_combo(args.device, args.select_code, args.start_code, args.kill)

if __name__ == "__main__":
    main()
