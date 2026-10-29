#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET="/opt/retropie/supplementary/splashscreen/asplashscreen.sh"
BACKUP_DIR="$SCRIPT_DIR/../backups/asplashscreen"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[[ -f "$TARGET" ]] || fail "Splash launcher not found: $TARGET"
sudo -n true 2>/dev/null || fail "Non-interactive sudo is required to update $TARGET"

mapfile -t option_lines < <(grep -E '^CMD_OPTS=' "$TARGET" || true)
((${#option_lines[@]} == 1)) ||
    fail "Expected exactly one CMD_OPTS assignment in $TARGET; found ${#option_lines[@]}"

line="${option_lines[0]}"
[[ "$line" =~ ^CMD_OPTS=\"([^\"]*)\"$ ]] ||
    fail "CMD_OPTS is not in the expected quoted format; refusing to edit it"

current_opts="${BASH_REMATCH[1]}"
read -r -a options <<< "$current_opts"
updated_options=()
window_count=0
skip_next=0

for option in "${options[@]}"; do
    if ((skip_next)); then
        skip_next=0
        continue
    fi

    if [[ "$option" == "--mmal-vout-window" ]]; then
        ((window_count += 1))
        ((window_count <= 1)) ||
            fail "Found multiple --mmal-vout-window options; refusing to guess which to change"
        skip_next=1
        continue
    fi

    if [[ "$option" == --mmal-vout-window=* ]]; then
        ((window_count += 1))
        ((window_count <= 1)) ||
            fail "Found multiple --mmal-vout-window options; refusing to guess which to change"
        continue
    fi

    updated_options+=("$option")
done

((skip_next == 0)) || fail "--mmal-vout-window has no value"

updated_options+=("--mmal-vout-window" "320x240+0+0")

new_opts=""
for option in "${updated_options[@]}"; do
    new_opts+="${new_opts:+ }$option"
done
new_line="CMD_OPTS=\" $new_opts\""

if [[ "$line" == "$new_line" ]]; then
    printf 'No change needed: %s already has the tested 320x240 splash window.\n' "$TARGET"
    exit 0
fi

mkdir -p -- "$BACKUP_DIR"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup="$BACKUP_DIR/asplashscreen.sh.pre-scaling-fix.$timestamp.bak"
suffix=1
while [[ -e "$backup" ]]; do
    backup="$BACKUP_DIR/asplashscreen.sh.pre-scaling-fix.$timestamp.$suffix.bak"
    ((suffix += 1))
done

sudo -n cp -p -- "$TARGET" "$backup"
temporary="$(mktemp)"
trap 'rm -f -- "$temporary"' EXIT

while IFS= read -r source_line || [[ -n "$source_line" ]]; do
    if [[ "$source_line" == CMD_OPTS=* ]]; then
        printf '%s\n' "$new_line"
    else
        printf '%s\n' "$source_line"
    fi
done < "$TARGET" > "$temporary"

sudo -n install -o root -g root -m 755 "$temporary" "$TARGET"
if ! sudo -n sh -n "$TARGET" ||
   ! grep -Fxq "$new_line" "$TARGET"; then
    sudo -n cp -p -- "$backup" "$TARGET"
    fail "Updated launcher failed validation; restored backup $backup"
fi

printf 'Updated boot splash scaling to 320x240+0+0.\n'
printf 'Backup: %s\n' "$backup"
printf 'The change applies to all splash files selected through RetroPie.\n'
