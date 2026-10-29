#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_HOST="${PICO8_SOURCE_HOST:-pi@192.168.178.75}"
SOURCE_HOME="${PICO8_SOURCE_HOME:-/home/pi}"
TARGET_HOME="${PICO8_TARGET_HOME:-/home/pi}"
BACKUP_ROOT="$TARGET_HOME/pico8-transfer-backups"
TARGET_ES_CONFIG="/etc/emulationstation/es_systems.cfg"
RUN_DIR=""
MANIFEST=""
DRY_RUN=0
ASSUME_YES=0

SOURCE_PATHS=(
    "Pico-8"
    "pico-8"
    ".lexaloffle/pico-8"
    "install/pico8"
    "RetroPie/roms/pico8"
    "scripts/python-superaio-custom-button"
)

usage() {
    cat <<EOF
Usage:
  $0                 Copy the licensed Pico-8 setup from the source Game Boy.
  $0 --dry-run       Inspect the source and target without writing anything.
  $0 --yes           Copy without the final replacement prompt.
  $0 --rollback DIR  Restore a previous transfer backup.
  $0 --help          Show this help.

Source defaults to $SOURCE_HOST:$SOURCE_HOME.
The copy includes Pico-8 runtimes, games, carts, user data, launchers,
controller helpers, and integration files. Redundant .tar and .zip installer
archives under install/pico8 are excluded.
Pico-8 launchers are normalized to use the target RetroPie combo-breaker hook
instead of starting the legacy custom-button monitor a second time.

The script must run on the target Game Boy. It creates a rollback backup
before replacing any target files.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

confirm_change() {
    local answer
    ((ASSUME_YES)) && return 0
    [[ -t 0 ]] || fail "Interactive approval requires a terminal. Use --yes to automate the transfer."
    while true; do
        printf '%s [y/N]: ' "$1"
        IFS= read -r answer </dev/tty || fail "Could not read approval."
        case "$answer" in
            y|Y|yes|YES|Yes) return 0 ;;
            ''|n|N|no|NO|No) return 1 ;;
            *) printf 'Please answer yes or no.\n' ;;
        esac
    done
}

source_preflight() {
    ssh "$SOURCE_HOST" "test -x '$SOURCE_HOME/Pico-8/pico8' &&
        test -f '$SOURCE_HOME/Pico-8/pico8.dat' &&
        test -f '$SOURCE_HOME/.lexaloffle/pico-8/config.txt' &&
        test -f '$SOURCE_HOME/.lexaloffle/pico-8/sdl_controllers.txt' &&
        test -d '$SOURCE_HOME/RetroPie/roms/pico8' &&
        test -d '$SOURCE_HOME/scripts/python-superaio-custom-button'"
}

source_manifest() {
    ssh "$SOURCE_HOST" "cd '$SOURCE_HOME' &&
        for root in ${SOURCE_PATHS[*]}; do
            if [ -d \"\$root\" ]; then
                find \"\$root\" -type f ! -name '*.tar' ! -name '*.zip' -print0
            fi
        done | sort -z | xargs -0 sha256sum"
}

target_manifest() {
    cd "$TARGET_HOME"
    for root in "${SOURCE_PATHS[@]}"; do
        if [[ -d "$root" ]]; then
            find "$root" -type f ! -name '*.tar' ! -name '*.zip' -print0
        fi
    done | sort -z | xargs -0 sha256sum
}

start_run() {
    local timestamp suffix=1
    timestamp="$(date +%Y%m%d-%H%M%S)"
    mkdir -p -- "$BACKUP_ROOT"
    RUN_DIR="$BACKUP_ROOT/$timestamp"
    while ! mkdir -- "$RUN_DIR" 2>/dev/null; do
        RUN_DIR="$BACKUP_ROOT/$timestamp-$suffix"
        ((suffix += 1))
    done
    chmod 700 "$RUN_DIR"
    MANIFEST="$RUN_DIR/changes.tsv"
    : > "$MANIFEST"
    chmod 600 "$MANIFEST"
    printf 'Transfer run: %s\n' "$RUN_DIR"
}

backup_entry() {
    local target="$1"
    local backup
    if [[ -e "$target" || -L "$target" ]]; then
        backup="$RUN_DIR/before$target"
        mkdir -p -- "$(dirname -- "$backup")"
        if [[ "$target" == /etc/* ]]; then
            sudo -n cp -a -- "$target" "$backup"
        else
            cp -a -- "$target" "$backup"
        fi
        printf 'RESTORE\t%s\t%s\n' "$target" "$backup" >> "$MANIFEST"
        printf 'BACKUP: %s\n' "$target"
    else
        printf 'REMOVE\t%s\t-\n' "$target" >> "$MANIFEST"
        printf 'NEW TARGET: %s\n' "$target"
    fi
}

install_emulationstation_entry() {
    cat <<'PY' | sudo -n python3 - "$TARGET_ES_CONFIG"
import os
import stat
import sys
import tempfile

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    content = source.read()

if "<name>pico8</name>" in content:
    print("EmulationStation already contains a pico8 system entry.")
    raise SystemExit(0)

snippet = """  <system>
    <name>pico8</name>
    <fullname>PICO-8</fullname>
    <path>/home/pi/RetroPie/roms/pico8</path>
    <extension>.sh .SH</extension>
    <command>/opt/retropie/supplementary/runcommand/runcommand.sh 0 %ROM%</command>
    <platform>pico8</platform>
    <theme>pico8</theme>
  </system>
"""
marker = "</systemList>"
if marker not in content:
    raise SystemExit("EmulationStation system list marker is missing")

updated = content.replace(marker, snippet + marker, 1)
metadata = os.stat(path)
descriptor, temporary = tempfile.mkstemp(
    prefix=".es_systems.cfg.", dir=os.path.dirname(path), text=True
)
try:
    with os.fdopen(descriptor, "w", encoding="utf-8") as output:
        output.write(updated)
    os.chmod(temporary, stat.S_IMODE(metadata.st_mode))
    os.chown(temporary, metadata.st_uid, metadata.st_gid)
    os.replace(temporary, path)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
print("Installed pico8 EmulationStation entry.")
PY
}

normalize_pico8_launchers() {
    local launcher
    while IFS= read -r -d '' launcher; do
        sed -i \
            '/python-superaio-custom-button\/custom-button\.py/d' \
            "$launcher"
    done < <(find "$TARGET_HOME/RetroPie/roms/pico8" -maxdepth 1 -type f -name '*.sh' -print0)
}

plan_transfer() {
    source_preflight || fail "Source Pico-8 setup is incomplete or inaccessible."
    printf 'DRY RUN ONLY\n'
    printf 'Source: %s:%s\n' "$SOURCE_HOST" "$SOURCE_HOME"
    printf 'Target: %s\n' "$TARGET_HOME"
    printf 'The following paths would be replaced:\n'
    printf '  %s\n' "${SOURCE_PATHS[@]}"
    printf 'Also updated: %s\n' "$TARGET_ES_CONFIG"
    printf '\nSource manifest:\n'
    source_manifest | wc -l
    printf 'Target paths currently present:\n'
    for path in "${SOURCE_PATHS[@]}"; do
        [[ -e "$TARGET_HOME/$path" ]] && printf '  present %s\n' "$TARGET_HOME/$path"
    done
    printf 'No files were changed.\n'
}

rollback_transfer() {
    local directory="$1"
    local action target backup

    [[ -d "$directory" ]] || fail "Backup directory does not exist: $directory"
    directory="$(cd -- "$directory" && pwd)"
    case "$directory" in
        "$BACKUP_ROOT"/*) ;;
        *) fail "Rollback directory must be inside $BACKUP_ROOT" ;;
    esac
    [[ -f "$directory/changes.tsv" ]] || fail "Transfer manifest is missing: $directory/changes.tsv"

    while IFS=$'\t' read -r action target backup; do
        [[ -n "$action" ]] || continue
        case "$action" in
            RESTORE)
                if [[ "$target" == /etc/* ]]; then
                    sudo -n rm -rf -- "$target"
                    sudo -n mkdir -p -- "$(dirname -- "$target")"
                    sudo -n cp -a -- "$backup" "$target"
                else
                    rm -rf -- "$target"
                    mkdir -p -- "$(dirname -- "$target")"
                    cp -a -- "$backup" "$target"
                fi
                printf 'RESTORED: %s\n' "$target"
                ;;
            REMOVE)
                if [[ "$target" == /etc/* ]]; then
                    sudo -n rm -rf -- "$target"
                else
                    rm -rf -- "$target"
                fi
                printf 'REMOVED CREATED PATH: %s\n' "$target"
                ;;
            *) fail "Unknown transfer action: $action" ;;
        esac
    done < "$directory/changes.tsv"
    printf 'Rollback complete.\n'
}

perform_transfer() {
    local source_hashes target_hashes
    source_preflight || fail "Source Pico-8 setup is incomplete or inaccessible."
    start_run
    backup_entry "$TARGET_HOME/Pico-8"
    backup_entry "$TARGET_HOME/pico-8"
    backup_entry "$TARGET_HOME/.lexaloffle/pico-8"
    backup_entry "$TARGET_HOME/install/pico8"
    backup_entry "$TARGET_HOME/RetroPie/roms/pico8"
    backup_entry "$TARGET_HOME/scripts/python-superaio-custom-button"
    backup_entry "$TARGET_ES_CONFIG"

    if ! confirm_change "Replace the target Pico-8 setup with the source copy?"; then
        printf 'Transfer cancelled.\n'
        return 0
    fi

    rm -rf -- \
        "$TARGET_HOME/Pico-8" \
        "$TARGET_HOME/pico-8" \
        "$TARGET_HOME/.lexaloffle/pico-8" \
        "$TARGET_HOME/install/pico8" \
        "$TARGET_HOME/RetroPie/roms/pico8" \
        "$TARGET_HOME/scripts/python-superaio-custom-button"
    mkdir -p -- "$TARGET_HOME" "$TARGET_HOME/RetroPie/roms"

    ssh "$SOURCE_HOST" \
        "tar --exclude='install/pico8/*.tar' --exclude='install/pico8/*.zip' -C '$SOURCE_HOME' -czf - ${SOURCE_PATHS[*]}" |
        tar -xzf - -C "$TARGET_HOME"

    chmod +x \
        "$TARGET_HOME/Pico-8"/pico8 \
        "$TARGET_HOME/Pico-8"/pico8_dyn \
        "$TARGET_HOME/Pico-8"/pico8_gpio \
        "$TARGET_HOME/pico-8"/pico8 \
        "$TARGET_HOME/pico-8"/pico8_dyn \
        "$TARGET_HOME/pico-8"/pico8_gpio \
        "$TARGET_HOME/RetroPie/roms/pico8"/*.sh \
        "$TARGET_HOME/scripts/python-superaio-custom-button"/*.py

    normalize_pico8_launchers
    install_emulationstation_entry
    source_hashes="$(source_manifest)"
    target_hashes="$(target_manifest)"
    printf '%s\n' "$source_hashes" > "$RUN_DIR/source.sha256"
    printf '%s\n' "$target_hashes" > "$RUN_DIR/target.sha256"
    if ! cmp -s "$RUN_DIR/source.sha256" "$RUN_DIR/target.sha256"; then
        fail "Source and target manifests differ. Rollback: $0 --rollback \"$RUN_DIR\""
    fi
    printf 'Transfer verified: source and target manifests match.\n'
    printf 'Rollback: %s --rollback \"%s\"\n' "$0" "$RUN_DIR"
}

main() {
    case "${1:-}" in
        --help|-h)
            usage
            ;;
        --dry-run)
            [[ $# -eq 1 ]] || { usage >&2; return 2; }
            plan_transfer
            ;;
        --yes)
            [[ $# -eq 1 ]] || { usage >&2; return 2; }
            ASSUME_YES=1
            perform_transfer
            ;;
        --rollback)
            [[ $# -eq 2 ]] || { usage >&2; return 2; }
            rollback_transfer "$2"
            ;;
        "")
            perform_transfer
            ;;
        *)
            usage >&2
            return 2
            ;;
    esac
}

main "$@"
