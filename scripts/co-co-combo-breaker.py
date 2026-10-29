#!/usr/bin/python3
import argparse
import configparser
import glob
import os
import re
import subprocess
import sys
import tempfile

try:
    from evdev import InputDevice, ecodes, list_devices
    EVDEV_IMPORT_ERROR = None
except ImportError as exc:
    InputDevice = None
    ecodes = None
    list_devices = None
    EVDEV_IMPORT_ERROR = exc


DEFAULT_DEVICE = "/dev/input/event4"
DEFAULT_DEVICE_STABLE_PATH = (
    "/dev/input/by-id/usb-Arduino_LLC_Arduino_Leonardo_HIDAF-if02-event-joystick"
)
DEFAULT_DEVICE_NAME = "Arduino LLC Arduino Leonardo"
DEFAULT_SELECT_CODE = 314
DEFAULT_START_CODE = 315
DEFAULT_KILL_PROCESSES = ["mame", "pico8"]
DEFAULT_CONFIG = "/home/pi/.config/super-aio/combo-breaker.conf"
PROCESS_NAME = re.compile(r"^[A-Za-z0-9_.+-]+$")


def require_evdev():
    if EVDEV_IMPORT_ERROR is not None:
        raise RuntimeError(
            "Python evdev is not installed; run install-saio.sh first"
        ) from EVDEV_IMPORT_ERROR


def is_kite_saio_board(name):
    normalized = name.casefold()
    return "arduino" in normalized and "leonardo" in normalized


def default_device_path():
    if os.path.exists(DEFAULT_DEVICE_STABLE_PATH):
        return DEFAULT_DEVICE_STABLE_PATH
    return DEFAULT_DEVICE


def stable_device_path(device_path):
    real_path = os.path.realpath(device_path)
    for pattern in ("/dev/input/by-id/*", "/dev/input/by-path/*"):
        for candidate in sorted(glob.glob(pattern)):
            if os.path.realpath(candidate) == real_path:
                return candidate
    return ""


def discover_devices():
    require_evdev()
    devices = []
    for path in list_devices():
        try:
            device = InputDevice(path)
            capabilities = device.capabilities()
        except OSError:
            continue
        devices.append(
            {
                "path": path,
                "name": device.name,
                "has_key": ecodes.EV_KEY in capabilities,
                "has_abs": ecodes.EV_ABS in capabilities,
                "stable_path": stable_device_path(path),
                "is_kite_board": is_kite_saio_board(device.name),
            }
        )
    return devices


def list_input_devices():
    devices = discover_devices()
    if not devices:
        print("No input devices found.")
        return

    print("Available input devices:")
    for device in devices:
        marker = " [standard Kite SAIO board]" if device["is_kite_board"] else ""
        stable = f", stable path: {device['stable_path']}" if device["stable_path"] else ""
        print(f"  {device['path']}: {device['name']}{marker}{stable}")


def key_name(code):
    require_evdev()
    names = ecodes.bytype.get(ecodes.EV_KEY, {})
    name = names.get(code, str(code))
    if isinstance(name, list):
        return name[0]
    return name


def resolve_device(device_path, device_name=None):
    require_evdev()
    if device_name and os.path.exists(device_path):
        device = InputDevice(device_path)
        if device.name == device_name:
            return device

    if device_name:
        for candidate in discover_devices():
            if candidate["name"] == device_name:
                return InputDevice(candidate["path"])

    return InputDevice(device_path)


def parse_config(config_path):
    parser = configparser.ConfigParser(interpolation=None)
    if not parser.read(config_path):
        raise ValueError(f"Configuration file not found: {config_path}")
    if "combo" not in parser:
        raise ValueError("Configuration is missing the [combo] section")

    section = parser["combo"]
    device_name = section.get("device_name", "").strip()
    device_path = section.get("device_path", "").strip()
    if not device_path:
        raise ValueError("Configuration must include device_path")

    combo_codes_raw = section.get("combo_codes", "").split()
    if combo_codes_raw:
        if len(combo_codes_raw) != 2:
            raise ValueError("combo_codes must contain exactly two button codes")
        try:
            combo_codes = [int(code) for code in combo_codes_raw]
        except ValueError as exc:
            raise ValueError("combo_codes must contain integers") from exc
    else:
        try:
            combo_codes = [
                section.getint("select_code"),
                section.getint("start_code"),
            ]
        except ValueError as exc:
            raise ValueError(
                "Configuration must include combo_codes or select_code/start_code"
            ) from exc

    kill_processes = section.get("kill_processes", "").split()
    if not kill_processes or any(not PROCESS_NAME.fullmatch(name) for name in kill_processes):
        raise ValueError("Configuration contains invalid process names")
    if combo_codes[0] == combo_codes[1]:
        raise ValueError("Combo button codes must be different")

    device = resolve_device(device_path, device_name or None)
    return {
        "device": device,
        "device_name": device_name,
        "device_path": device.path,
        "combo_codes": combo_codes,
        "select_code": combo_codes[0],
        "start_code": combo_codes[1],
        "kill_processes": kill_processes,
    }


def prompt_yes_no(prompt, default=True):
    suffix = "[Y/n]" if default else "[y/N]"
    while True:
        answer = input(f"{prompt} {suffix} ").strip().casefold()
        if not answer:
            return default
        if answer in {"y", "yes"}:
            return True
        if answer in {"n", "no"}:
            return False
        print("Please answer yes or no.")


def gamepad_candidates(devices):
    candidates = [
        device
        for device in devices
        if device["has_key"] and not device["is_kite_board"]
    ]
    return sorted(candidates, key=lambda device: device["path"])


def choose_gamepad():
    devices = discover_devices()
    default_device = next(
        (
            device
            for device in devices
            if device["name"] == DEFAULT_DEVICE_NAME and device["has_key"]
        ),
        None,
    )
    if default_device and prompt_yes_no(
        f"Use the default Kite SAIO gamepad {default_device['path']} "
        f"({default_device['name']})?"
    ):
        return InputDevice(default_device["path"])

    candidates = gamepad_candidates(devices)

    if not candidates:
        raise RuntimeError(
            "No gamepad-like input device found. Connect the gamepad and try again."
        )

    print("\nSelectable input devices:")
    for index, device in enumerate(candidates, start=1):
        stable = f" ({device['stable_path']})" if device["stable_path"] else ""
        print(f"  {index}. {device['path']}: {device['name']}{stable}")

    if len(candidates) == 1:
        selected = candidates[0]
        if not prompt_yes_no(
            f"Use {selected['path']} ({selected['name']}) for the combo?"
        ):
            raise RuntimeError("Gamepad selection cancelled.")
        return InputDevice(selected["path"])

    while True:
        answer = input(f"Select the gamepad number [1-{len(candidates)}]: ").strip()
        try:
            index = int(answer) - 1
        except ValueError:
            index = -1
        if 0 <= index < len(candidates):
            return InputDevice(candidates[index]["path"])
        print("Please select one of the listed numbers.")


def choose_default_gamepad():
    for path in (DEFAULT_DEVICE_STABLE_PATH, DEFAULT_DEVICE):
        try:
            return InputDevice(path)
        except OSError:
            continue

    for candidate in discover_devices():
        if candidate["name"] == DEFAULT_DEVICE_NAME:
            return InputDevice(candidate["path"])
    return None


def capture_combo(device):
    print(
        "\nPress and hold the two buttons you want to use together, "
        "then release both."
    )
    try:
        device.grab()
    except OSError:
        print("Warning: could not exclusively grab the device; continuing.")

    active_codes = []
    captured_codes = None
    released_codes = set()
    try:
        for event in device.read_loop():
            if event.type != ecodes.EV_KEY:
                continue
            if captured_codes is None and event.value == 1:
                if event.code not in active_codes:
                    active_codes.append(event.code)
                    print(
                        f"Button detected: code={event.code} "
                        f"({key_name(event.code)})"
                    )
                if len(active_codes) == 2:
                    captured_codes = tuple(active_codes)
                    print(
                        "Combo detected: "
                        + " + ".join(
                            f"{code} ({key_name(code)})"
                            for code in captured_codes
                        )
                    )
            elif captured_codes is None and event.value == 0:
                if event.code in active_codes:
                    active_codes.remove(event.code)
            elif (
                captured_codes is not None
                and event.code in captured_codes
                and event.value == 0
            ):
                released_codes.add(event.code)
                if len(released_codes) == len(captured_codes):
                    break
    finally:
        try:
            device.ungrab()
        except OSError:
            pass

    if captured_codes is None:
        raise RuntimeError("Could not read two buttons for the combo.")
    return list(captured_codes)


def write_config(config_path, device, combo_codes):
    parent = os.path.dirname(os.path.abspath(config_path))
    parent_exists = os.path.isdir(parent)
    os.makedirs(parent, mode=0o700, exist_ok=True)
    if not parent_exists:
        os.chmod(parent, 0o700)

    path = (
        (stable_device_path(device.path) or device.path)
        if device
        else default_device_path()
    )
    parser = configparser.ConfigParser()
    parser["combo"] = {
        "device_name": device.name if device else "",
        "device_path": path,
        "combo_codes": " ".join(str(code) for code in combo_codes),
        "select_code": str(combo_codes[0]),
        "start_code": str(combo_codes[1]),
        "kill_processes": " ".join(DEFAULT_KILL_PROCESSES),
    }

    descriptor, temporary_path = tempfile.mkstemp(
        prefix=".combo-breaker.", dir=parent, text=True
    )
    try:
        with os.fdopen(descriptor, "w") as output:
            parser.write(output)
        os.chmod(temporary_path, 0o600)
        os.replace(temporary_path, config_path)
    finally:
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)


def create_default_config(config_path):
    device = choose_default_gamepad()
    write_config(
        config_path,
        device,
        [DEFAULT_SELECT_CODE, DEFAULT_START_CODE],
    )
    if device:
        print(
            f"Created default combo-breaker configuration for {device.name} "
            f"({device.path})"
        )
    else:
        print(
            f"Created default combo-breaker configuration using {DEFAULT_DEVICE}; "
            "connect the gamepad before validating it"
        )
    print(
        f"SELECT={DEFAULT_SELECT_CODE}, START={DEFAULT_START_CODE}, "
        f"processes={','.join(DEFAULT_KILL_PROCESSES)}"
    )


def configure_combo(config_path):
    device = choose_gamepad()
    combo_codes = capture_combo(device)

    print(
        "\nSaved combo mapping: "
        + " + ".join(
            f"{code} ({key_name(code)})" for code in combo_codes
        )
    )
    if not prompt_yes_no("Save this combo-breaker configuration?", default=True):
        raise RuntimeError("Combo-breaker configuration cancelled.")

    write_config(config_path, device, combo_codes)
    print(f"Saved combo-breaker configuration to {config_path}")


def identify_buttons(device_path, device_name=None):
    try:
        device = resolve_device(device_path, device_name)
        print(f"Listening on {device.path} ({device.name})")
        print("Press buttons to see their codes. Press Ctrl+C to exit.")
        for event in device.read_loop():
            if event.type == ecodes.EV_KEY:
                print(
                    f"Key event: code={event.code} ({key_name(event.code)}), "
                    f"value={event.value}"
                )
    except (OSError, RuntimeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


def monitor_combo(device, combo_codes, kill_processes):
    print(
        f"Monitoring for the configured two-button combo on "
        f"{device.path} ({device.name})..."
    )
    pressed_codes = set()
    for event in device.read_loop():
        if event.type != ecodes.EV_KEY:
            continue
        pressed = event.value in (1, 2)
        if event.code in combo_codes:
            if pressed:
                pressed_codes.add(event.code)
            else:
                pressed_codes.discard(event.code)
        if all(code in pressed_codes for code in combo_codes):
            print(
                f"Configured combo detected! Killing: {', '.join(kill_processes)}"
            )
            for process in kill_processes:
                subprocess.call(["killall", "-9", process])
            break


def build_parser():
    parser = argparse.ArgumentParser(
        description=(
            "Co-Co-Combo Breaker: Identify button codes or monitor for "
            "a configured two-button combo to kill emulators."
        )
    )
    parser.add_argument(
        "--device",
        "-d",
        default=None,
        help=f"Input device path (default: {DEFAULT_DEVICE})",
    )
    parser.add_argument(
        "--identify",
        action="store_true",
        help="Identify button codes (prints all key events)",
    )
    parser.add_argument(
        "--combo",
        action="store_true",
        help="Monitor for the configured two-button combo and kill processes",
    )
    parser.add_argument(
        "--configure",
        action="store_true",
        help="Select a gamepad and capture two buttons pressed together",
    )
    parser.add_argument(
        "--create-default-config",
        action="store_true",
        help="Create a config with the default device and button codes",
    )
    parser.add_argument(
        "--check-config",
        action="store_true",
        help="Validate the saved combo-breaker configuration and device",
    )
    parser.add_argument(
        "--select-code",
        type=int,
        default=None,
        help=f"Button code for SELECT (default: {DEFAULT_SELECT_CODE})",
    )
    parser.add_argument(
        "--start-code",
        type=int,
        default=None,
        help=f"Button code for START (default: {DEFAULT_START_CODE})",
    )
    parser.add_argument(
        "--kill",
        nargs="+",
        default=None,
        help=(
            "Process names to kill on combo "
            f"(default: {' '.join(DEFAULT_KILL_PROCESSES)})"
        ),
    )
    parser.add_argument(
        "--list-devices",
        action="store_true",
        help="List available input devices and exit",
    )
    parser.add_argument(
        "--config",
        default=DEFAULT_CONFIG,
        help=f"Saved configuration path (default: {DEFAULT_CONFIG})",
    )
    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    if args.list_devices:
        list_input_devices()
        return 0

    if args.configure:
        try:
            configure_combo(args.config)
        except (OSError, RuntimeError, ValueError) as exc:
            print(f"Error: {exc}", file=sys.stderr)
            return 1
        return 0

    if args.create_default_config:
        try:
            create_default_config(args.config)
        except (OSError, RuntimeError, ValueError) as exc:
            print(f"Error: {exc}", file=sys.stderr)
            return 1
        return 0

    if args.check_config:
        try:
            configuration = parse_config(args.config)
        except (OSError, RuntimeError, ValueError) as exc:
            print(f"Invalid combo-breaker configuration: {exc}", file=sys.stderr)
            return 1
        print(
            f"Combo-breaker configuration OK: {configuration['device'].path} "
            f"({configuration['device'].name})"
        )
        return 0

    if not (
        args.identify
        or args.combo
        or args.configure
        or args.create_default_config
        or args.check_config
    ):
        if not os.path.exists(args.config):
            try:
                create_default_config(args.config)
            except (OSError, RuntimeError, ValueError) as exc:
                print(f"Error: {exc}", file=sys.stderr)
                return 1
            return 0
        parser.print_help()
        return 0

    configuration = None
    if os.path.exists(args.config):
        try:
            configuration = parse_config(args.config)
        except (OSError, RuntimeError, ValueError) as exc:
            print(f"Invalid combo-breaker configuration: {exc}", file=sys.stderr)
            return 1

    device_name = configuration["device_name"] if configuration else None
    device_path = (
        args.device
        or (configuration["device"].path if configuration else None)
        or default_device_path()
    )
    configured_combo = (
        configuration["combo_codes"]
        if configuration
        else [DEFAULT_SELECT_CODE, DEFAULT_START_CODE]
    )
    combo_codes = [
        args.select_code
        if args.select_code is not None
        else configured_combo[0],
        args.start_code
        if args.start_code is not None
        else configured_combo[1],
    ]
    kill_processes = (
        args.kill
        if args.kill is not None
        else (
            configuration["kill_processes"]
            if configuration
            else DEFAULT_KILL_PROCESSES
        )
    )

    try:
        device = resolve_device(device_path, device_name)
    except (OSError, RuntimeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    if args.identify:
        return identify_buttons(device.path, device.name)
    monitor_combo(device, combo_codes, kill_processes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
