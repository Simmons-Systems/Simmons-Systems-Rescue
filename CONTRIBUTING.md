# Contributing to Simmons-Systems-Rescue

Thanks for considering a contribution. Bug reports, docs fixes, additional
hardware tests, and build-script improvements are all welcome.

## Dev setup

```bash
git clone https://github.com/Simmons-Systems/Simmons-Systems-Rescue.git
cd Simmons-Systems-Rescue
pre-commit install
```

You'll need: `bash`, `shellcheck`, `shfmt`, `xz`, `dosfstools`, `parted`,
`util-linux` (for `losetup`), and (for end-to-end testing) a spare USB stick
and a target box that boots from USB.

## Running the tests

```bash
./tests/shellcheck.sh                       # lints autorun/, bin/, config/
./bin/build-rescue-usb.sh --dry-run --output /tmp/test.img    # builds image, no real USB
```

End-to-end is real-iron: flash to a USB, boot a NUC (or VM with USB
passthrough), confirm autorun fires and `poweroff` is reached.

## Adding a new test to the autorun harness

Tests live in `autorun/tests/` and are run in lexical order. Naming convention
is `NN-name.sh` where `NN` controls run order:

- `10-` inventory (cheap, runs first so we have it even if later tests fail)
- `20-` storage / SMART
- `30-` memory
- `40-` CPU / IO stress
- `50-` network

Each test is a self-contained bash script that:

- Sources `autorun/lib.sh` for `log()`, `pass()`, `fail()`, `section()` helpers.
- Writes human-readable output to stdout (the autorun captures it).
- Exits 0 on pass, non-zero on fail with a one-line summary at the top.

## Code style

- `pre-commit run --all-files` must be clean.
- Bash: `set -euo pipefail`, double-quote variable expansions, prefer `[[ ]]` over `[ ]`.
- Comments explain WHY, not WHAT — well-named identifiers handle the latter.

## PR checklist

- [ ] `pre-commit run --all-files` is clean.
- [ ] If you added a test, `./tests/shellcheck.sh` passes.
- [ ] If you changed the build scripts, `--dry-run --output /tmp/test.img` produces a valid image.
- [ ] README and docs updated if public behaviour changed.
- [ ] `CHANGELOG.md` updated under `[Unreleased]`.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be respectful; assume good faith.
