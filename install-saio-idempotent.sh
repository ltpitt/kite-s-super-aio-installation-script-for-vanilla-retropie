#!/usr/bin/env bash
set -Eeuo pipefail

SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SOURCE="$SETUP_DIR/configs"
BACKUP_ROOT="$SETUP_DIR/backups/install-saio"
CONFIG_ROOT="/opt/retropie/configs"
BOOT_ROOT="/boot"
RUNCOMMAND_SOURCE="$SETUP_DIR/scripts"
RUN_DIR=""
LOG_FILE=""
MANIFEST=""
SNAPSHOT_MAP=""
declare -A RECORDED_TARGETS=()

usage() {
    cat <<EOF
Usage:
  $0                 Snapshot active configs, then interactively apply config templates.
  $0 --snapshot-only Snapshot active configs and exit without proposing changes.
  $0 --rollback DIR  Restore files changed by a previous run in DIR.
  $0 --help          Show this help.

This script only manages configuration files. It does not install packages,
clone repositories, change services, enable SSH, change Wi-Fi credentials,
or reboot the system.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_sudo() {
    sudo -n true 2>/dev/null ||
        fail "Non-interactive sudo is required to back up or update system configs."
}

start_run() {
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    umask 077
    mkdir -p -- "$BACKUP_ROOT"
    RUN_DIR="$BACKUP_ROOT/$timestamp"
    local suffix=1
    while ! mkdir -- "$RUN_DIR" 2>/dev/null; do
        RUN_DIR="$BACKUP_ROOT/$timestamp-$suffix"
        ((suffix += 1))
    done
    chmod 700 "$RUN_DIR"
    mkdir -p -- "$RUN_DIR/snapshot" "$RUN_DIR/before"
    LOG_FILE="$RUN_DIR/run.log"
    MANIFEST="$RUN_DIR/changes.tsv"
    SNAPSHOT_MAP="$RUN_DIR/snapshot.tsv"
    : > "$MANIFEST"
    : > "$SNAPSHOT_MAP"
    chmod 600 "$MANIFEST" "$SNAPSHOT_MAP"
    exec > >(tee -a "$LOG_FILE") 2>&1
    printf 'Run started: %s\n' "$(date --iso-8601=seconds)"
    printf 'Run directory: %s\n' "$RUN_DIR"
}

snapshot_file() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    local destination="$RUN_DIR/snapshot$path"
    mkdir -p -- "$(dirname -- "$destination")"
    sudo -n cp -a -- "$path" "$destination"
    printf '%s\t%s\n' "$path" "$destination" >> "$SNAPSHOT_MAP"
    printf 'SNAPSHOT: %s\n' "$path"
}

snapshot_configs() {
    local path
    local directory
    printf '\nCreating timestamped snapshot of active configuration files...\n'

    for path in \
        "$BOOT_ROOT/config.txt" \
        "$BOOT_ROOT/config-saio.txt" \
        /etc/asound.conf \
        /home/pi/.asoundrc \
        "$CONFIG_ROOT/all/autostart.sh" \
        "$CONFIG_ROOT/all/runcommand-onstart.sh" \
        "$CONFIG_ROOT/all/runcommand-onend.sh" \
        "$CONFIG_ROOT/all/splashscreen.cfg" \
        "$CONFIG_ROOT/fba/fba2x.cfg" \
        "$CONFIG_ROOT/mame-mame4all/mame.cfg" \
        "$CONFIG_ROOT/psx/emulators.cfg" \
        "$CONFIG_ROOT/psx/pcsx/pcsx.cfg" \
        /opt/retropie/supplementary/splashscreen/asplashscreen.sh \
        /etc/systemd/system/saio.service
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

    if [[ -f "$target" ]]; then
        local backup="$RUN_DIR/before$target"
        mkdir -p -- "$(dirname -- "$backup")"
        sudo -n cp -a -- "$target" "$backup"
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
    [[ -t 0 ]] || fail "Interactive confirmation requires a terminal."
    while true; do
        printf '%s [y/N]: ' "$prompt"
        IFS= read -r answer </dev/tty || fail "Could not read confirmation."
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

    if [[ ! -f "$source" ]]; then
        printf '\nSKIP: %s (source is missing: %s)\n' "$description" "$source"
        return 0
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
    sudo -n install -D -o root -g root -m 0644 -- "$source" "$target"
    cmp -s -- "$source" "$target" || fail "Post-copy verification failed for $target"
    printf 'APPLIED: %s\n' "$target"
}

apply_asoundrc_if_missing() {
    local target="/home/pi/.asoundrc"
    local proposed
    proposed="$(printf 'pcm.!default {\n\ttype hw\n\tcard 1\n}\n\nctl.!default {\n\ttype hw\n\tcard 1\n}')"
    [[ -e "$target" ]] && {
        printf '\nSKIP: user ALSA config already exists: %s\n' "$target"
        return 0
    }

    printf '\n=== Create user ALSA configuration ===\n'
    printf 'Current file: %s (does not exist)\nProposed configuration:\n' "$target"
    printf '%s\n' "$proposed" | sed 's/^/  /'
    if ! confirm_change "Create this file?"; then
        return 0
    fi

    record_before_change "$target"
    printf '%s\n' "$proposed" > "$target"
    printf 'APPLIED: %s\n' "$target"
}

rollback_run() {
    local directory="$1"
    local action target backup

    case "$directory" in
        "$BACKUP_ROOT"/*) ;;
        *) fail "Rollback directory must be inside $BACKUP_ROOT" ;;
    esac
    [[ -d "$directory" ]] || fail "Run directory does not exist: $directory"
    [[ -f "$directory/changes.tsv" ]] || fail "No change manifest found in $directory"
    require_sudo
    printf 'Rolling back changes recorded in %s\n' "$directory/changes.tsv"

    while IFS=$'\t' read -r action target backup; do
        [[ -n "$action" ]] || continue
        [[ "$target" == /* && "$target" != "/" ]] ||
            fail "Unsafe target in change manifest: $target"
        [[ ! -d "$target" ]] || fail "Refusing to replace a directory: $target"
        case "$action" in
            RESTORE)
                [[ -f "$backup" ]] || fail "Required backup is missing: $backup"
                sudo -n cp -a -- "$backup" "$target"
                printf 'RESTORED: %s\n' "$target"
                ;;
            REMOVE)
                if [[ -e "$target" ]]; then
                    sudo -n rm -f -- "$target"
                    printf 'REMOVED CREATED FILE: %s\n' "$target"
                else
                    printf 'ALREADY ABSENT: %s\n' "$target"
                fi
                ;;
            *)
                fail "Unknown action in change manifest: $action"
                ;;
        esac
    done < "$directory/changes.tsv"
    printf 'Rollback complete.\n'
}

preflight() {
    local required
    for required in \
        "$CONFIG_SOURCE/config.txt" \
        "$CONFIG_SOURCE/config-saio.txt" \
        "$CONFIG_SOURCE/asound.conf" \
        "$CONFIG_SOURCE/fba2x.cfg" \
        "$CONFIG_SOURCE/mame.cfg" \
        "$RUNCOMMAND_SOURCE/runcommand_onstart.sh" \
        "$RUNCOMMAND_SOURCE/runcommand_onend.sh"
    do
        [[ -f "$required" ]] || fail "Required template is missing: $required"
    done
    require_sudo
}

main() {
    local mode="${1:-}"
    case "$mode" in
        --help|-h)
            usage
            return 0
            ;;
        --rollback)
            [[ $# -eq 2 ]] || {
                usage >&2
                return 2
            }
            rollback_run "$2"
            return 0
            ;;
        --snapshot-only|"")
            [[ $# -le 1 ]] || {
                usage >&2
                return 2
            }
            ;;
        *)
            usage >&2
            return 2
            ;;
    esac

    preflight
    if [[ ! -t 0 && "$mode" != "--snapshot-only" ]]; then
        fail "Interactive config changes require a terminal. Use --snapshot-only for a non-interactive backup."
    fi

    start_run
    snapshot_configs

    if [[ "$mode" == "--snapshot-only" ]]; then
        printf 'Snapshot-only run complete; no active configuration was changed.\n'
        return 0
    fi

    printf '\nConfiguration templates will be proposed one file at a time.\n'
    printf 'Packages, repository clones, services, SSH enablement, and reboot are not managed here.\n'

    apply_template "$CONFIG_SOURCE/config.txt" "$BOOT_ROOT/config.txt" "Raspberry Pi boot config"
    apply_template "$CONFIG_SOURCE/config-saio.txt" "$BOOT_ROOT/config-saio.txt" "Super-AIO boot config"
    apply_template "$CONFIG_SOURCE/asound.conf" /etc/asound.conf "System ALSA config"
    apply_asoundrc_if_missing
    apply_template "$CONFIG_SOURCE/fba2x.cfg" "$CONFIG_ROOT/fba/fba2x.cfg" "PiFBA config"
    apply_template "$CONFIG_SOURCE/mame.cfg" "$CONFIG_ROOT/mame-mame4all/mame.cfg" "MAME4All main config"
    apply_template "$RUNCOMMAND_SOURCE/runcommand_onstart.sh" "$CONFIG_ROOT/all/runcommand-onstart.sh" "RetroPie game-start hook"
    apply_template "$RUNCOMMAND_SOURCE/runcommand_onend.sh" "$CONFIG_ROOT/all/runcommand-onend.sh" "RetroPie game-end hook"

    if [[ -f "$SETUP_DIR/autostart.sh" ]]; then
        apply_template "$SETUP_DIR/autostart.sh" "$CONFIG_ROOT/all/autostart.sh" "EmulationStation autostart config"
    else
        printf '\nSKIP: EmulationStation autostart template is missing.\n'
    fi

    if [[ -f "$SETUP_DIR/wpa_supplicant.conf" ]]; then
        printf '\nSKIP: Wi-Fi configuration is intentionally not copied because it contains credentials.\n'
        printf 'Configure Wi-Fi separately using a secret-safe workflow.\n'
    else
        printf '\nSKIP: Optional Wi-Fi template is missing.\n'
    fi

    printf '\nNo reboot was performed. Review the log and backups in %s\n' "$RUN_DIR"
    printf 'To roll back accepted changes, run:\n  %s --rollback "%s"\n' "$0" "$RUN_DIR"
}

main "$@"
