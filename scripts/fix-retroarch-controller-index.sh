#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/opt/retropie/configs/all/retroarch.cfg"
BACKUP_DIR="$SCRIPT_DIR/../backups/retroarch-controller-index"
SETTING="input_player1_joypad_index"

usage() {
    cat <<EOF
Usage:
  $0                 Set RetroArch player 1 to controller index 0.
  $0 --rollback      Restore the newest backup made by this script.
  $0 --rollback FILE Restore the specified backup made by this script.
EOF
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

ensure_retroarch_stopped() {
    if pgrep -x retroarch >/dev/null 2>&1; then
        fail "RetroArch is running. Exit the game before changing its configuration."
    fi
}

restore_config() {
    local backup="$1"
    [[ -f "$backup" ]] || fail "Backup not found: $backup"
    [[ "$(basename -- "$backup")" == retroarch.cfg.pre-player1-index.*.bak ]] ||
        fail "Not a player-index backup created by this script: $backup"
    ensure_retroarch_stopped
    cp -p -- "$backup" "$CONFIG_FILE"
    printf 'Restored %s from %s\n' "$CONFIG_FILE" "$backup"
}

case "${1:-}" in
    "")
        ;;
    --rollback)
        if [[ $# -gt 2 ]]; then
            usage >&2
            exit 2
        fi
        if [[ $# -eq 2 ]]; then
            restore_config "$2"
        else
            shopt -s nullglob
            backups=("$BACKUP_DIR"/retroarch.cfg.pre-player1-index.*.bak)
            ((${#backups[@]} > 0)) || fail "No script-created backups found in $BACKUP_DIR"
            latest="$(ls -1t -- "${backups[@]}" | sed -n '1p')"
            restore_config "$latest"
        fi
        exit 0
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

[[ -f "$CONFIG_FILE" ]] || fail "RetroArch config not found: $CONFIG_FILE"

matches="$(grep -Ec "^[[:space:]]*${SETTING}[[:space:]]*=" "$CONFIG_FILE" || true)"
[[ "$matches" == "1" ]] ||
    fail "Expected exactly one active $SETTING setting in $CONFIG_FILE; found $matches"

line="$(grep -E "^[[:space:]]*${SETTING}[[:space:]]*=" "$CONFIG_FILE")"
if [[ "$line" =~ ^[[:space:]]*input_player1_joypad_index[[:space:]]*=[[:space:]]*\"?([0-9]+)\"?[[:space:]]*(#.*)?$ ]]; then
    current_index="${BASH_REMATCH[1]}"
else
    fail "Could not parse the active $SETTING setting: $line"
fi

if [[ "$current_index" == "0" ]]; then
    printf 'No change needed: player 1 already uses controller index 0.\n'
    exit 0
fi

ensure_retroarch_stopped
mkdir -p -- "$BACKUP_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"
backup="$BACKUP_DIR/retroarch.cfg.pre-player1-index.$timestamp.bak"
suffix=1
while [[ -e "$backup" ]]; do
    backup="$BACKUP_DIR/retroarch.cfg.pre-player1-index.$timestamp.$suffix.bak"
    ((suffix += 1))
done

cp -p -- "$CONFIG_FILE" "$backup"
temporary="$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
cp -p -- "$CONFIG_FILE" "$temporary"
sed -i -E \
    's/^([[:space:]]*input_player1_joypad_index[[:space:]]*=[[:space:]]*).*/\1"0"/' \
    "$temporary"
mv -f -- "$temporary" "$CONFIG_FILE"
trap - EXIT

printf 'Set player 1 controller index from %s to 0.\n' "$current_index"
printf 'Backup: %s\n' "$backup"
printf 'Rollback: %s --rollback "%s"\n' "$0" "$backup"
