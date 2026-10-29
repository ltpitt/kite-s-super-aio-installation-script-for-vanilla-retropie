# Kite SAIO / Super-AIO Installation for RetroPie

This repository contains an idempotent setup installer for the **Kite SAIO / Super-AIO** control board on vanilla RetroPie, including Game Boy Zero builds running on Raspberry Pi Zero hardware. It complements the upstream [kiteretro/Super-AIO](https://github.com/kiteretro/Super-AIO) project with safe installation, controller, emulator, audio, display, and rollback configuration.

## Install

Run the single setup entry point from the Raspberry Pi checkout:

```bash
chmod +x install-saio.sh scripts/*.sh
./install-saio.sh
```

The installer checks existing state before changing anything, shows diffs, asks for approval, creates backups, and does not reboot automatically.

## Installer modes

```bash
./install-saio.sh --help
./install-saio.sh --dry-run
./install-saio.sh --snapshot-only
./install-saio.sh --rollback BACKUP_DIRECTORY
```

Use `--dry-run` before the first real run. The installer help is the authoritative source for current emulator checks, paths, combo-breaker behavior, rollback details, and command-specific prerequisites.

## Included utilities

- `scripts/co-co-combo-breaker.py` configures and monitors a two-button emulator-exit combo.
- `scripts/sync-roms-from-usb.sh` synchronizes supported ROMs from USB storage.
- `scripts/fix-asplashscreen-scaling.sh` and `scripts/fix-retroarch-controller-index.sh` apply targeted, backed-up repairs.

## Safety

- No `xboxdrv` dependency.
- Wi-Fi credentials are not copied or included in backups.
- Existing user configuration is preserved unless an approved change explicitly targets it.
- Run backups are stored below `backups/` and are ignored by Git.

See `AGENTS.md` for repository contribution guidance.
