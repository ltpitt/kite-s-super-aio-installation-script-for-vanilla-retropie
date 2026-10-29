#!/usr/bin/env bash
set -Eeuo pipefail

SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SOURCE="$SETUP_DIR/configs"
SCRIPT_SOURCE="$SETUP_DIR/scripts"
BACKUP_ROOT="$SETUP_DIR/backups/install-saio"

REPO_URL="https://github.com/geebles/Super-AIO.git"
REPO_PATH="/home/pi/Super-AIO"
SAIO_RELEASE_PATH="$REPO_PATH/release/saio"
PI_USER="pi"
PI_HOME="/home/$PI_USER"
PI_GROUP="$(id -gn "$PI_USER" 2>/dev/null || printf '%s' "$PI_USER")"

CONFIG_ROOT="/opt/retropie/configs"
BOOT_ROOT="/boot"
AUTOSTART_TARGET="$CONFIG_ROOT/all/autostart.sh"
RUNCOMMAND_START_TARGET="$CONFIG_ROOT/all/runcommand-onstart.sh"
RUNCOMMAND_END_TARGET="$CONFIG_ROOT/all/runcommand-onend.sh"
FBA_TARGET="$CONFIG_ROOT/fba/fba2x.cfg"
MAME_TARGET="$CONFIG_ROOT/mame-mame4all/mame.cfg"
ASOUND_TARGET="/etc/asound.conf"
USER_ASOUND_TARGET="$PI_HOME/.asoundrc"
SYSTEMD_SERVICE="/etc/systemd/system/saio.service"
SSH_MARKER="$BOOT_ROOT/ssh"
COMBO_CONFIG="$PI_HOME/.config/super-aio/combo-breaker.conf"
COMBO_BREAKER_TARGET="$PI_HOME/.local/lib/super-aio/co-co-combo-breaker.py"

RUN_DIR=""
LOG_FILE=""
MANIFEST=""
SNAPSHOT_MAP=""
STATE_FILE=""
APT_UPDATED=0
TEMPLATE_CHANGED=0
declare -A RECORDED_TARGETS=()

usage() {
    cat <<EOF
Usage:
  $0                 Bootstrap missing dependencies and apply approved configuration changes.
  $0 --dry-run       Inspect the device and print the complete planned command sequence.
  $0 --snapshot-only Snapshot active configs and exit without changing the system.
  $0 --rollback DIR  Restore files and service state from a previous run in DIR.
  $0 --help          Show this help.

Every change is checked against the current system and proposed individually.
Backups, logs, and a rollback manifest are stored below:
  $BACKUP_ROOT

This script does not copy Wi-Fi credentials or reboot the system.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

as_root() {
    if ((EUID == 0)); then
        "$@"
    else
        sudo "$@"
    fi
}

as_pi() {
    if [[ "$(id -un)" == "$PI_USER" ]]; then
        "$@"
    elif command -v runuser >/dev/null 2>&1; then
        as_root runuser -u "$PI_USER" -- "$@"
    else
        "$@"
    fi
}

require_privileges() {
    ((EUID == 0)) || sudo -v || fail "Sudo authentication is required."
}

package_installed() {
    local package="$1"
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
        grep -q '^install ok installed$'
}

evdev_importable() {
    python3 -c 'import evdev' >/dev/null 2>&1
}

start_run() {
    local timestamp suffix=1
    timestamp="$(date +%Y%m%d-%H%M%S)"
    umask 077
    mkdir -p -- "$BACKUP_ROOT"
    RUN_DIR="$BACKUP_ROOT/$timestamp"
    while ! mkdir -- "$RUN_DIR" 2>/dev/null; do
        RUN_DIR="$BACKUP_ROOT/$timestamp-$suffix"
        ((suffix += 1))
    done
    chmod 700 "$RUN_DIR"
    mkdir -p -- "$RUN_DIR/snapshot" "$RUN_DIR/before"

    LOG_FILE="$RUN_DIR/run.log"
    MANIFEST="$RUN_DIR/changes.tsv"
    SNAPSHOT_MAP="$RUN_DIR/snapshot.tsv"
    STATE_FILE="$RUN_DIR/state.tsv"
    : > "$MANIFEST"
    : > "$SNAPSHOT_MAP"
    : > "$STATE_FILE"
    chmod 600 "$MANIFEST" "$SNAPSHOT_MAP" "$STATE_FILE"

    exec > >(tee -a "$LOG_FILE") 2>&1
    printf 'Run started: %s\n' "$(date --iso-8601=seconds)"
    printf 'Run directory: %s\n' "$RUN_DIR"
}

state_set() {
    printf '%s\t%s\n' "$1" "$2" >> "$STATE_FILE"
}

state_get() {
    local key="$1"
    awk -F '\t' -v key="$key" '$1 == key { print $2; exit }' "$STATE_FILE"
}

capture_initial_state() {
    local service_enabled service_active

    state_set repo_present "$([[ -e "$REPO_PATH" ]] && printf yes || printf no)"
    state_set libpng12_0 "$(package_installed libpng12-0 && printf installed || printf missing)"
    state_set python_serial "$(package_installed python-serial && printf installed || printf missing)"
    state_set python3_pip "$(package_installed python3-pip && printf installed || printf missing)"
    state_set evdev_import "$(evdev_importable && printf present || printf missing)"
    state_set evdev_pip "$(python3 -m pip show evdev >/dev/null 2>&1 && printf present || printf missing)"
    state_set ssh_marker "$([[ -e "$SSH_MARKER" ]] && printf present || printf missing)"
    state_set service_file "$([[ -e "$SYSTEMD_SERVICE" ]] && printf present || printf missing)"

    service_enabled="$(as_root systemctl is-enabled saio.service 2>/dev/null || true)"
    service_active="$(as_root systemctl is-active saio.service 2>/dev/null || true)"
    [[ -n "$service_enabled" ]] || service_enabled="not-enabled"
    [[ -n "$service_active" ]] || service_active="inactive"
    state_set service_enabled "$service_enabled"
    state_set service_active "$service_active"
}

snapshot_file() {
    local path="$1"
    [[ -f "$path" ]] || return 0

    local destination="$RUN_DIR/snapshot$path"
    mkdir -p -- "$(dirname -- "$destination")"
    as_root cp -a -- "$path" "$destination"
    printf '%s\t%s\n' "$path" "$destination" >> "$SNAPSHOT_MAP"
    printf 'SNAPSHOT: %s\n' "$path"
}

snapshot_configs() {
    local path directory
    printf '\nCreating timestamped snapshot of active configuration files...\n'

    for path in \
        "$BOOT_ROOT/config.txt" \
        "$BOOT_ROOT/config-saio.txt" \
        "$ASOUND_TARGET" \
        "$USER_ASOUND_TARGET" \
        "$AUTOSTART_TARGET" \
        "$RUNCOMMAND_START_TARGET" \
        "$RUNCOMMAND_END_TARGET" \
        "$CONFIG_ROOT/all/splashscreen.cfg" \
        "$FBA_TARGET" \
        "$MAME_TARGET" \
        "$CONFIG_ROOT/psx/emulators.cfg" \
        "$CONFIG_ROOT/psx/pcsx/pcsx.cfg" \
        "$COMBO_CONFIG" \
        "$COMBO_BREAKER_TARGET" \
        /opt/retropie/supplementary/splashscreen/asplashscreen.sh \
        "$SYSTEMD_SERVICE"
    do
        snapshot_file "$path"
    done

    for directory in \
        "$CONFIG_ROOT/mame-mame4all/cfg" \
        "$CONFIG_ROOT/mame-mame4all/inp" \
        "$CONFIG_ROOT/psx/pcsx/cfg"
    do
        [[ -d "$directory" ]] || continue
        while IFS= read -r -d '' path; do
            snapshot_file "$path"
        done < <(find "$directory" -type f \( -name '*.cfg' -o -name '*.inp' \) -print0)
    done

    if [[ -d "$CONFIG_ROOT" ]]; then
        while IFS= read -r -d '' path; do
            snapshot_file "$path"
        done < <(find "$CONFIG_ROOT" -type f -name retroarch.cfg -print0)
    fi

    printf 'Snapshot contains %s active config files.\n' "$(wc -l < "$SNAPSHOT_MAP")"
    printf 'Sensitive Wi-Fi credentials are intentionally excluded from snapshots and logs.\n'
}

record_before_change() {
    local target="$1"
    [[ -n "${RECORDED_TARGETS[$target]+x}" ]] && return 0

    if [[ -e "$target" || -L "$target" ]]; then
        [[ ! -d "$target" ]] || fail "Refusing to back up a directory as a file: $target"
        local backup="$RUN_DIR/before$target"
        mkdir -p -- "$(dirname -- "$backup")"
        as_root cp -a -- "$target" "$backup"
        printf 'RESTORE\t%s\t%s\n' "$target" "$backup" >> "$MANIFEST"
        printf 'CHANGE BACKUP: %s\n' "$backup"
    else
        printf 'REMOVE\t%s\t-\n' "$target" >> "$MANIFEST"
        printf 'ROLLBACK NOTE: %s will be removed if this run is rolled back.\n' "$target"
    fi
    RECORDED_TARGETS["$target"]=1
}

confirm_change() {
    local prompt="$1"
    local answer

    [[ -t 0 ]] || fail "Interactive approval requires a terminal."
    while true; do
        printf '%s [y/N]: ' "$prompt"
        IFS= read -r answer </dev/tty || fail "Could not read approval."
        case "$answer" in
            y|Y|yes|YES|Yes)
                printf 'Decision: approved\n'
                return 0
                ;;
            ''|n|N|no|NO|No)
                printf 'Decision: skipped\n'
                return 1
                ;;
            *)
                printf 'Please answer yes or no.\n'
                ;;
        esac
    done
}

apply_template() {
    local source="$1"
    local target="$2"
    local description="$3"
    local owner="${4:-root}"
    local group="${5:-root}"
    local mode="${6:-0644}"

    TEMPLATE_CHANGED=0
    [[ -f "$source" ]] || fail "Required template is missing: $source"
    if [[ -e "$target" && ! -f "$target" && ! -L "$target" ]]; then
        fail "Target is not a regular file: $target"
    fi

    printf '\n=== %s ===\n' "$description"
    if [[ -f "$target" ]] && cmp -s -- "$source" "$target"; then
        printf 'Current file already matches the proposed configuration; no change needed.\n'
        return 0
    fi

    if [[ -f "$target" ]]; then
        printf 'Current file: %s\nProposed file: %s\n' "$target" "$source"
        diff -u --label "current: $target" --label "proposed: $source" "$target" "$source" || true
    else
        printf 'Current file: %s (does not exist)\nProposed configuration:\n' "$target"
        sed 's/^/  /' "$source"
    fi

    if ! confirm_change "Apply this configuration?"; then
        return 0
    fi

    record_before_change "$target"
    as_root install -D -o "$owner" -g "$group" -m "$mode" -- "$source" "$target"
    cmp -s -- "$source" "$target" || fail "Post-copy verification failed for $target"
    TEMPLATE_CHANGED=1
    printf 'APPLIED: %s\n' "$target"
}

apply_user_asoundrc() {
    local target="$USER_ASOUND_TARGET"
    local proposed_file
    if [[ -e "$target" ]]; then
        printf '\n=== User ALSA configuration ===\n'
        printf 'SKIP: user ALSA config already exists: %s\n' "$target"
        return 0
    fi

    proposed_file="$(mktemp)"
    printf 'pcm.!default {\n\ttype hw\n\tcard 1\n}\n\nctl.!default {\n\ttype hw\n\tcard 1\n}\n' > "$proposed_file"

    printf '\n=== User ALSA configuration ===\n'
    printf 'Current file: %s (does not exist)\nProposed configuration:\n' "$target"
    sed 's/^/  /' "$proposed_file"
    if confirm_change "Create the user ALSA configuration?"; then
        record_before_change "$target"
        as_root install -D -o "$PI_USER" -g "$PI_GROUP" -m 0644 -- "$proposed_file" "$target"
        printf 'APPLIED: %s\n' "$target"
    fi
    rm -f -- "$proposed_file"
}

ensure_package() {
    local package="$1"
    if package_installed "$package"; then
        printf 'PACKAGE OK: %s\n' "$package"
        return 0
    fi

    printf '\nPACKAGE MISSING: %s\n' "$package"
    if ! confirm_change "Install the missing package $package?"; then
        fail "Required package is missing: $package"
    fi

    if ((APT_UPDATED == 0)); then
        printf 'Refreshing package lists...\n'
        as_root apt-get update
        APT_UPDATED=1
    fi
    as_root apt-get install -y "$package"
    package_installed "$package" || fail "Package installation did not complete: $package"
    printf 'INSTALLED: %s\n' "$package"
}

ensure_repository() {
    local required
    if [[ ! -e "$REPO_PATH" ]]; then
        printf '\nSuper-AIO repository is missing: %s\n' "$REPO_PATH"
        if ! confirm_change "Clone Super-AIO from $REPO_URL?"; then
            fail "Super-AIO is required but was not cloned."
        fi
        as_pi git clone --depth=1 "$REPO_URL" "$REPO_PATH"
    elif [[ ! -d "$SAIO_RELEASE_PATH" ]]; then
        fail "Super-AIO exists but its release directory is missing: $SAIO_RELEASE_PATH"
    else
        printf 'REPOSITORY OK: %s\n' "$REPO_PATH"
    fi

    for required in \
        "$SAIO_RELEASE_PATH/saio-osd.py" \
        "$SAIO_RELEASE_PATH/python-serial_2.6-1.1_all.deb" \
        "$SAIO_RELEASE_PATH/autostart.sh"
    do
        [[ -f "$required" ]] || fail "Super-AIO checkout is incomplete; missing $required"
    done
}

ensure_python_serial() {
    local package="python-serial"
    if package_installed "$package"; then
        printf 'PACKAGE OK: %s\n' "$package"
        return 0
    fi

    printf '\nPACKAGE MISSING: %s\n' "$package"
    if ! confirm_change "Install the bundled Python serial package?"; then
        fail "Required package is missing: $package"
    fi
    as_root dpkg -i "$SAIO_RELEASE_PATH/python-serial_2.6-1.1_all.deb" ||
        as_root apt-get install -f -y
    package_installed "$package" || fail "Package installation did not complete: $package"
    printf 'INSTALLED: %s\n' "$package"
}

ensure_evdev() {
    if evdev_importable; then
        printf 'PYTHON MODULE OK: evdev\n'
        return 0
    fi

    printf '\nPYTHON MODULE MISSING: evdev\n'
    if ! confirm_change "Install the Python evdev module?"; then
        fail "Required Python module is missing: evdev"
    fi
    ensure_package python3-pip
    as_root python3 -m pip install evdev
    evdev_importable || fail "Python evdev installation did not complete."
    printf 'INSTALLED: Python evdev module\n'
}

combo_config_valid() {
    as_pi python3 "$COMBO_BREAKER_TARGET" \
        --check-config \
        --config "$COMBO_CONFIG" >/dev/null 2>&1
}

ensure_combo_program() {
    apply_template \
        "$SCRIPT_SOURCE/co-co-combo-breaker.py" \
        "$COMBO_BREAKER_TARGET" \
        "Installed combo-breaker runtime" \
        "$PI_USER" \
        "$PI_GROUP" \
        0644
}

ensure_combo_config() {
    if combo_config_valid; then
        printf 'COMBO BREAKER CONFIG OK: %s\n' "$COMBO_CONFIG"
        return 0
    fi

    if [[ ! -f "$COMBO_CONFIG" ]]; then
        printf '\nCombo-breaker configuration is missing.\n'
        printf 'The installer can create the documented combo-breaker defaults:\n'
        printf '  device: Arduino LLC Arduino Leonardo (event4/by-id when available)\n'
        printf '  SELECT: 314\n'
        printf '  START: 315\n'
        printf '  processes: mame pico8\n'
        if ! confirm_change "Create the default combo-breaker configuration?"; then
            printf 'SKIPPED: combo-breaker default configuration\n'
            return 0
        fi

        record_before_change "$COMBO_CONFIG"
        as_pi env COMBO_BREAKER_INIT_ONLY=1 python3 "$COMBO_BREAKER_TARGET" \
            --config "$COMBO_CONFIG"
        if combo_config_valid; then
            printf 'DEFAULT COMBO BREAKER CONFIGURED: %s\n' "$COMBO_CONFIG"
        else
            printf 'WARNING: default combo-breaker config was created but the device is not currently valid.\n'
            printf 'Reconnect the gamepad and run --configure if needed.\n'
        fi
        return 0
    fi

    printf '\nCombo breaker is not configured for the current gamepad.\n'
    printf 'The wizard will default to the Kite SAIO Arduino Leonardo,\n'
    printf 'then capture two buttons pressed together.\n'
    if ! confirm_change "Configure the two-button combo exit now?"; then
        printf 'SKIPPED: combo-breaker gamepad configuration\n'
        return 0
    fi

    record_before_change "$COMBO_CONFIG"
    as_pi python3 "$COMBO_BREAKER_TARGET" \
        --configure \
        --config "$COMBO_CONFIG"
    combo_config_valid || fail "Combo-breaker configuration did not validate."
    printf 'COMBO BREAKER CONFIGURED: %s\n' "$COMBO_CONFIG"
}

ensure_executable_group() {
    local description="$1"
    shift
    local file
    local -a missing=()

    for file in "$@"; do
        [[ -f "$file" ]] || continue
        [[ -x "$file" ]] || missing+=("$file")
    done
    ((${#missing[@]} == 0)) && {
        printf 'PERMISSIONS OK: %s\n' "$description"
        return 0
    }

    printf '\nEXECUTABLE PERMISSIONS MISSING for %s:\n' "$description"
    printf '  %s\n' "${missing[@]}"
    if ! confirm_change "Make these files executable?"; then
        fail "Required executable permissions are missing: $description"
    fi
    for file in "${missing[@]}"; do
        record_before_change "$file"
        as_root chmod +x -- "$file"
    done
    printf 'APPLIED: executable permissions for %s\n' "$description"
}

apply_ssh_marker() {
    [[ -e "$SSH_MARKER" ]] && {
        printf 'SSH MARKER OK: %s\n' "$SSH_MARKER"
        return 0
    }

    printf '\nSSH marker is missing: %s\n' "$SSH_MARKER"
    if ! confirm_change "Create the SSH enablement marker?"; then
        printf 'SKIPPED: SSH marker\n'
        return 0
    fi
    record_before_change "$SSH_MARKER"
    as_root install -D -o root -g root -m 0644 /dev/null "$SSH_MARKER"
    printf 'APPLIED: %s\n' "$SSH_MARKER"
}

write_service_template() {
    service_template > "$RUN_DIR/saio.service.proposed"
}

service_enabled() {
    as_root systemctl is-enabled --quiet saio.service
}

service_active() {
    as_root systemctl is-active --quiet saio.service
}

service_enabled_readonly() {
    systemctl is-enabled --quiet saio.service
}

service_active_readonly() {
    systemctl is-active --quiet saio.service
}

ensure_service() {
    local service_changed
    write_service_template
    apply_template \
        "$RUN_DIR/saio.service.proposed" \
        "$SYSTEMD_SERVICE" \
        "Super-AIO systemd service"
    service_changed="$TEMPLATE_CHANGED"

    if ((service_changed)); then
        as_root systemctl daemon-reload
    fi

    if ! service_enabled; then
        if confirm_change "Enable saio.service at boot?"; then
            as_root systemctl enable saio.service
        else
            fail "saio.service must be enabled for the installed setup."
        fi
    else
        printf 'SERVICE ENABLED: saio.service\n'
    fi

    if service_active; then
        if ((service_changed)); then
            if confirm_change "Restart saio.service to apply the updated service definition?"; then
                as_root systemctl restart saio.service
            else
                printf 'SKIPPED: service restart; the new definition will apply after the next restart.\n'
            fi
        else
            printf 'SERVICE ACTIVE: saio.service\n'
        fi
    else
        if confirm_change "Start saio.service now?"; then
            as_root systemctl start saio.service
            service_active || fail "saio.service failed to start."
            printf 'SERVICE STARTED: saio.service\n'
        else
            fail "saio.service must be running for the installed setup."
        fi
    fi
}

restore_manifest() {
    local manifest="$1"
    local action target backup

    while IFS=$'\t' read -r action target backup; do
        [[ -n "$action" ]] || continue
        [[ "$target" == /* && "$target" != "/" ]] ||
            fail "Unsafe target in change manifest: $target"
        [[ ! -d "$target" ]] || fail "Refusing to replace a directory: $target"
        case "$action" in
            RESTORE)
                [[ -f "$backup" || -L "$backup" ]] ||
                    fail "Required backup is missing: $backup"
                as_root mkdir -p -- "$(dirname -- "$target")"
                as_root cp -a -- "$backup" "$target"
                printf 'RESTORED: %s\n' "$target"
                ;;
            REMOVE)
                if [[ -e "$target" || -L "$target" ]]; then
                    as_root rm -f -- "$target"
                    printf 'REMOVED CREATED FILE: %s\n' "$target"
                else
                    printf 'ALREADY ABSENT: %s\n' "$target"
                fi
                ;;
            *)
                fail "Unknown action in change manifest: $action"
                ;;
        esac
    done < "$manifest"
}

rollback_service_state() {
    local file_before enabled_before active_before
    file_before="$(state_get service_file)"
    enabled_before="$(state_get service_enabled)"
    active_before="$(state_get service_active)"

    if [[ "$file_before" != present ]]; then
        if service_active; then
            as_root systemctl stop saio.service
        fi
        if service_enabled; then
            as_root systemctl disable saio.service
        fi
    fi

    as_root systemctl daemon-reload
    [[ "$file_before" == present ]] || return 0

    case "$enabled_before" in
        enabled|static|indirect)
            service_enabled || as_root systemctl enable saio.service
            ;;
        *)
            if service_enabled; then
                as_root systemctl disable saio.service
            fi
            ;;
    esac

    case "$active_before" in
        active)
            if service_active; then
                as_root systemctl restart saio.service
            else
                as_root systemctl start saio.service
            fi
            ;;
        *)
            if service_active; then
                as_root systemctl stop saio.service
            fi
            ;;
    esac
}

rollback_dependency() {
    local package="$1"
    local before
    before="$(state_get "$package")"
    [[ "$before" == missing ]] || return 0
    if ! package_installed "$package"; then
        return 0
    fi

    printf '\nDependency installed by the run: %s\n' "$package"
    if confirm_change "Remove $package as part of this rollback?"; then
        as_root apt-get remove -y "$package"
    else
        printf 'RETAINED: %s\n' "$package"
    fi
}

rollback_evdev() {
    [[ "$(state_get evdev_import)" == missing ]] || return 0
    evdev_importable || return 0

    printf '\nPython module installed by the run: evdev\n'
    if confirm_change "Remove the evdev module as part of this rollback?"; then
        as_root python3 -m pip uninstall -y evdev
    else
        printf 'RETAINED: Python evdev module\n'
    fi
}

rollback_repository() {
    [[ "$(state_get repo_present)" == no ]] || return 0
    [[ -d "$REPO_PATH/.git" ]] || return 0

    if [[ -n "$(git -C "$REPO_PATH" status --porcelain --untracked-files=all)" ]]; then
        printf 'RETAINED: %s has changes since it was cloned; refusing to remove it.\n' "$REPO_PATH"
        return 0
    fi

    printf '\nRepository cloned by the run: %s\n' "$REPO_PATH"
    if confirm_change "Remove the clean Super-AIO clone as part of this rollback?"; then
        as_root rm -rf -- "$REPO_PATH"
    else
        printf 'RETAINED: %s\n' "$REPO_PATH"
    fi
}

rollback_run() {
    local directory="$1"

    [[ -d "$directory" ]] || fail "Run directory does not exist: $directory"
    directory="$(cd -- "$directory" && pwd)"
    case "$directory" in
        "$BACKUP_ROOT"/*) ;;
        *) fail "Rollback directory must be inside $BACKUP_ROOT" ;;
    esac
    [[ -f "$directory/changes.tsv" ]] || fail "No change manifest found in $directory"
    [[ -f "$directory/state.tsv" ]] || fail "No state record found in $directory"

    RUN_DIR="$directory"
    MANIFEST="$directory/changes.tsv"
    STATE_FILE="$directory/state.tsv"
    require_privileges
    printf 'Rolling back changes recorded in %s\n' "$MANIFEST"

    rollback_service_state
    restore_manifest "$MANIFEST"
    rollback_dependency libpng12_0
    rollback_dependency python_serial
    rollback_dependency python3_pip
    rollback_evdev
    rollback_repository
    rollback_service_state
    printf 'Rollback complete.\n'
}

preflight() {
    local required
    for required in \
        "$CONFIG_SOURCE/asound.conf" \
        "$CONFIG_SOURCE/config.txt" \
        "$CONFIG_SOURCE/config-saio.txt" \
        "$CONFIG_SOURCE/fba2x.cfg" \
        "$CONFIG_SOURCE/mame.cfg" \
        "$SCRIPT_SOURCE/runcommand_onstart.sh" \
        "$SCRIPT_SOURCE/runcommand_onend.sh" \
        "$SCRIPT_SOURCE/co-co-combo-breaker.py"
    do
        [[ -f "$required" ]] || fail "Required repository file is missing: $required"
    done
}

PLAN_APT_UPDATE=0

plan_template() {
    local source="$1"
    local target="$2"
    local description="$3"
    local owner="${4:-root}"
    local group="${5:-root}"
    local mode="${6:-0644}"

    printf '\n[%s]\n' "$description"
    if [[ ! -f "$source" ]]; then
        printf 'BLOCKED: source is missing: %s\n' "$source"
        return 0
    fi
    if [[ -f "$target" ]] && cmp -s -- "$source" "$target"; then
        printf 'SKIP: active file already matches.\n'
        return 0
    fi

    if [[ -f "$target" ]]; then
        printf 'WOULD UPDATE: %s\n' "$target"
        diff -u --label "current: $target" --label "proposed: $source" "$target" "$source" || true
    else
        printf 'WOULD CREATE: %s\n' "$target"
    fi
    printf 'COMMAND: sudo install -D -o %s -g %s -m %s %q %q\n' \
        "$owner" "$group" "$mode" "$source" "$target"
}

plan_user_asoundrc() {
    local proposed
    proposed="$(printf 'pcm.!default {\n\ttype hw\n\tcard 1\n}\n\nctl.!default {\n\ttype hw\n\tcard 1\n}\n')"

    printf '\n[User ALSA configuration]\n'
    if [[ -e "$USER_ASOUND_TARGET" ]]; then
        printf 'SKIP: preserve existing user ALSA config: %s\n' "$USER_ASOUND_TARGET"
        return 0
    fi
    printf 'WOULD CREATE: %s\n' "$USER_ASOUND_TARGET"
    printf 'COMMAND: sudo install -D -o %s -g %s -m 0644 /dev/stdin %q <<\\''EOF\\''\n%sEOF\n' \
        "$PI_USER" "$PI_GROUP" "$USER_ASOUND_TARGET" "$proposed"
}

plan_package() {
    local package="$1"
    if package_installed "$package"; then
        printf 'SKIP PACKAGE: %s is already installed.\n' "$package"
        return 0
    fi

    printf '\n[Package: %s]\n' "$package"
    if ((PLAN_APT_UPDATE == 0)); then
        printf 'COMMAND: sudo apt-get update\n'
        PLAN_APT_UPDATE=1
    fi
    printf 'COMMAND: sudo apt-get install -y %q\n' "$package"
}

plan_repository() {
    local required
    printf '\n[Super-AIO repository]\n'
    if [[ -d "$SAIO_RELEASE_PATH" ]]; then
        printf 'SKIP: repository and release directory already exist.\n'
    elif [[ ! -e "$REPO_PATH" ]]; then
        printf 'WOULD CLONE: %s\n' "$REPO_PATH"
        printf 'COMMAND: git clone --depth=1 %q %q\n' "$REPO_URL" "$REPO_PATH"
        return 0
    else
        printf 'BLOCKED: %s exists but its release directory is missing.\n' "$REPO_PATH"
        return 0
    fi

    for required in \
        "$SAIO_RELEASE_PATH/saio-osd.py" \
        "$SAIO_RELEASE_PATH/python-serial_2.6-1.1_all.deb" \
        "$SAIO_RELEASE_PATH/autostart.sh"
    do
        if [[ -f "$required" ]]; then
            printf 'CHECK: present %s\n' "$required"
        else
            printf 'BLOCKED: required repository file is missing: %s\n' "$required"
        fi
    done
}

plan_python_serial() {
    printf '\n[Python serial package]\n'
    if package_installed python-serial; then
        printf 'SKIP PACKAGE: python-serial is already installed.\n'
        return 0
    fi
    printf 'COMMAND: sudo dpkg -i %q\n' "$SAIO_RELEASE_PATH/python-serial_2.6-1.1_all.deb"
    printf 'FALLBACK COMMAND: sudo apt-get install -f -y\n'
}

plan_evdev() {
    printf '\n[Python evdev module]\n'
    if evdev_importable; then
        printf 'SKIP MODULE: evdev imports successfully.\n'
        return 0
    fi
    printf 'CHECK: python3-pip\n'
    plan_package python3-pip
    printf 'COMMAND: sudo python3 -m pip install evdev\n'
}

plan_combo_program() {
    plan_template \
        "$SCRIPT_SOURCE/co-co-combo-breaker.py" \
        "$COMBO_BREAKER_TARGET" \
        "Installed combo-breaker runtime" \
        "$PI_USER" \
        "$PI_GROUP" \
        0644
}

plan_combo_config() {
    local helper="$COMBO_BREAKER_TARGET"
    printf '\n[Combo-breaker configuration]\n'
    if [[ ! -f "$COMBO_BREAKER_TARGET" ]]; then
        helper="$SCRIPT_SOURCE/co-co-combo-breaker.py"
        printf 'NOTE: runtime helper will be installed before this check.\n'
    fi
    if [[ -f "$COMBO_CONFIG" ]] &&
        python3 "$helper" --check-config >/dev/null 2>&1; then
        printf 'SKIP: configuration is valid for the current device.\n'
        return 0
    fi
    if [[ ! -f "$COMBO_CONFIG" ]]; then
        printf 'WOULD CREATE DEFAULT CONFIG: %s\n' "$COMBO_CONFIG"
        printf 'COMMAND: COMBO_BREAKER_INIT_ONLY=1 python3 %q\n' "$COMBO_BREAKER_TARGET"
    else
        printf 'WOULD RECONFIGURE: %s\n' "$COMBO_CONFIG"
        printf 'COMMAND: python3 %q --configure\n' "$COMBO_BREAKER_TARGET"
    fi
}

plan_executable_group() {
    local description="$1"
    shift
    local file
    local missing=()

    for file in "$@"; do
        [[ -f "$file" ]] || continue
        [[ -x "$file" ]] || missing+=("$file")
    done
    if ((${#missing[@]} == 0)); then
        printf 'SKIP PERMISSIONS: %s are already executable.\n' "$description"
        return 0
    fi
    printf '\n[Executable permissions: %s]\n' "$description"
    printf 'COMMAND: sudo chmod +x --'
    printf ' %q' "${missing[@]}"
    printf '\n'
}

service_template() {
    cat <<EOF
[Unit]
Description=Super-AIO Service
After=network.target

[Service]
ExecStart=/usr/bin/nice -n 19 /usr/bin/python $SAIO_RELEASE_PATH/saio-osd.py
Restart=always

[Install]
WantedBy=multi-user.target

EOF
}

plan_service() {
    local service_changed=0
    printf '\n[Super-AIO systemd service]\n'
    if [[ -f "$SYSTEMD_SERVICE" ]] &&
        cmp -s <(service_template) "$SYSTEMD_SERVICE"; then
        printf 'SKIP: service file already matches.\n'
    else
        service_changed=1
        if [[ -f "$SYSTEMD_SERVICE" ]]; then
            printf 'WOULD UPDATE: %s\n' "$SYSTEMD_SERVICE"
            diff -u \
                --label "current: $SYSTEMD_SERVICE" \
                --label "proposed: $SYSTEMD_SERVICE" \
                "$SYSTEMD_SERVICE" <(service_template) || true
        else
            printf 'WOULD CREATE: %s\n' "$SYSTEMD_SERVICE"
        fi
        printf 'COMMAND: write generated unit to %q\n' "$SYSTEMD_SERVICE"
        printf 'COMMAND: sudo systemctl daemon-reload\n'
    fi

    if service_enabled_readonly; then
        printf 'SKIP: saio.service is enabled.\n'
    else
        printf 'COMMAND: sudo systemctl enable saio.service\n'
    fi
    if service_active_readonly; then
        if ((service_changed)); then
            printf 'COMMAND: sudo systemctl restart saio.service\n'
        else
            printf 'SKIP: saio.service is active.\n'
        fi
    else
        printf 'COMMAND: sudo systemctl start saio.service\n'
    fi
}

run_dry_run() {
    local -a saio_binaries setup_scripts

    preflight
    PLAN_APT_UPDATE=0
    printf 'DRY RUN ONLY: no sudo authentication, writes, package changes, service changes, or reboot.\n'
    printf 'The following is the ordered plan for the current device state.\n'

    plan_repository
    plan_package libpng12-0
    plan_python_serial
    plan_evdev
    plan_combo_program
    plan_combo_config

    saio_binaries=(
        "$SAIO_RELEASE_PATH/../tester/pngview"
        "$SAIO_RELEASE_PATH/osd/saio-osd"
        "$SAIO_RELEASE_PATH/rfkill/rfkill"
        "$SAIO_RELEASE_PATH/flash/flash.sh"
    )
    shopt -s nullglob
    setup_scripts=("$SCRIPT_SOURCE"/*.sh "$SCRIPT_SOURCE"/*.py)
    plan_executable_group "Super-AIO binaries" "${saio_binaries[@]}"
    plan_executable_group "repository setup scripts" "${setup_scripts[@]}"

    plan_template "$CONFIG_SOURCE/config.txt" "$BOOT_ROOT/config.txt" "Raspberry Pi boot config"
    plan_template "$CONFIG_SOURCE/config-saio.txt" "$BOOT_ROOT/config-saio.txt" "Super-AIO boot config"
    plan_template "$CONFIG_SOURCE/asound.conf" "$ASOUND_TARGET" "System ALSA config"
    plan_user_asoundrc
    plan_template "$CONFIG_SOURCE/fba2x.cfg" "$FBA_TARGET" "PiFBA config"
    plan_template "$CONFIG_SOURCE/mame.cfg" "$MAME_TARGET" "MAME4All main config"
    plan_template "$SAIO_RELEASE_PATH/autostart.sh" "$AUTOSTART_TARGET" "EmulationStation autostart config"
    plan_template "$SCRIPT_SOURCE/runcommand_onstart.sh" "$RUNCOMMAND_START_TARGET" "RetroPie game-start hook" root root 0755
    plan_template "$SCRIPT_SOURCE/runcommand_onend.sh" "$RUNCOMMAND_END_TARGET" "RetroPie game-end hook" root root 0755

    printf '\n[SSH enablement marker]\n'
    if [[ -e "$SSH_MARKER" ]]; then
        printf 'SKIP: %s already exists.\n' "$SSH_MARKER"
    else
        printf 'COMMAND: sudo install -D -o root -g root -m 0644 /dev/null %q\n' "$SSH_MARKER"
    fi

    plan_service
    printf '\nEND DRY RUN: no changes were made.\n'
}

run_installation() {
    local -a saio_binaries setup_scripts

    require_privileges
    preflight
    start_run
    capture_initial_state
    snapshot_configs

    if [[ "${1:-}" == "--snapshot-only" ]]; then
        printf 'Snapshot-only run complete; no active configuration was changed.\n'
        return 0
    fi

    ensure_repository
    ensure_package libpng12-0
    ensure_python_serial
    ensure_evdev
    ensure_combo_program
    ensure_combo_config

    saio_binaries=(
        "$SAIO_RELEASE_PATH/../tester/pngview"
        "$SAIO_RELEASE_PATH/osd/saio-osd"
        "$SAIO_RELEASE_PATH/rfkill/rfkill"
        "$SAIO_RELEASE_PATH/flash/flash.sh"
    )
    shopt -s nullglob
    setup_scripts=("$SCRIPT_SOURCE"/*.sh "$SCRIPT_SOURCE"/*.py)
    ensure_executable_group "Super-AIO binaries" "${saio_binaries[@]}"
    ensure_executable_group "repository setup scripts" "${setup_scripts[@]}"

    printf '\nConfiguration changes will be proposed one file at a time.\n'
    apply_template "$CONFIG_SOURCE/config.txt" "$BOOT_ROOT/config.txt" "Raspberry Pi boot config"
    apply_template "$CONFIG_SOURCE/config-saio.txt" "$BOOT_ROOT/config-saio.txt" "Super-AIO boot config"
    apply_template "$CONFIG_SOURCE/asound.conf" "$ASOUND_TARGET" "System ALSA config"
    apply_user_asoundrc
    apply_template "$CONFIG_SOURCE/fba2x.cfg" "$FBA_TARGET" "PiFBA config"
    apply_template "$CONFIG_SOURCE/mame.cfg" "$MAME_TARGET" "MAME4All main config"
    apply_template "$SAIO_RELEASE_PATH/autostart.sh" "$AUTOSTART_TARGET" "EmulationStation autostart config"
    apply_template "$SCRIPT_SOURCE/runcommand_onstart.sh" "$RUNCOMMAND_START_TARGET" "RetroPie game-start hook" root root 0755
    apply_template "$SCRIPT_SOURCE/runcommand_onend.sh" "$RUNCOMMAND_END_TARGET" "RetroPie game-end hook" root root 0755
    apply_ssh_marker
    ensure_service

    printf '\nInstallation run complete. No reboot was performed.\n'
    printf 'Review the log and backups in %s\n' "$RUN_DIR"
    printf 'To roll back accepted changes, run:\n  %s --rollback "%s"\n' "$0" "$RUN_DIR"
}

main() {
    case "${1:-}" in
        --help|-h)
            usage
            ;;
        --rollback)
            [[ $# -eq 2 ]] || {
                usage >&2
                return 2
            }
            rollback_run "$2"
            ;;
        --dry-run)
            [[ $# -eq 1 ]] || {
                usage >&2
                return 2
            }
            run_dry_run
            ;;
        --snapshot-only|"")
            [[ $# -le 1 ]] || {
                usage >&2
                return 2
            }
            run_installation "${1:-}"
            ;;
        *)
            usage >&2
            return 2
            ;;
    esac
}

main "$@"
