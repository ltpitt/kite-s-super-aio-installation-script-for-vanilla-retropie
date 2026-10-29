# Agent instructions

## Documentation is part of every user-visible change

Every user-visible functional change must review and update `README.md` in the same change. Keep the README concise: document the stable basics, safety impact, and the primary command or workflow, while detailed and changing options belong in the relevant `--help` output.

Do not duplicate the full CLI help in README.md or let the two drift. If a functional change has no stable README-level impact, keep the README unchanged and ensure the relevant online help or command output is updated.

## Repository conventions

- `install-saio.sh` is the only setup entry point.
- The installer must remain idempotent and interactive: skip matching state, show diffs, and ask before each accepted change.
- `install-saio.sh --dry-run` must remain read-only and report the complete ordered plan.
- Keep backups and rollback manifests under `backups/`; this directory is intentionally ignored by Git.
- Never copy Wi-Fi credentials into snapshots or logs.
- Do not reintroduce `xboxdrv`.
- The legacy Super-AIO service uses Python 2; the combo breaker uses Python 3 and `evdev`.
- Check Pi Zero emulator availability through RetroPie-Setup module IDs and expected binaries before proposing installation.
- Preserve existing user-owned configurations when they are already working, especially ALSA and controller mappings.

## Validation

For shell changes, run `bash -n install-saio.sh scripts/*.sh` and `sh -n` for POSIX hooks. For Python changes, run `python3 -m py_compile` on changed Python files. Run `git diff --check`, and use the dry-run mode or a read-only device check when the change affects installer behavior.
