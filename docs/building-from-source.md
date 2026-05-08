# Building from source

This is what `bin/build-rescue-usb.sh` and `build-memtest-usb.sh` do under the
hood, in case you want to understand or extend them.

## `build-rescue-usb.sh` flow

1. **Download SystemRescue ISO** from `fastly-cdn.system-rescue.org` at the
   pinned version (`SYSRESCUE_VERSION=13.00` by default; override via env var).
2. **Verify the upstream GPG signature.** Imports the SystemRescue release
   key from `keyserver.ubuntu.com` (fallback `keys.openpgp.org`) the first
   time, then `gpg --verify` against the `.asc` file. Build halts on
   verification failure.
3. **Cache** the verified ISO under `.cache/` so subsequent builds skip the
   download.
4. **Allocate a target image:** either a sparse file (`--output dist/rescue.img`)
   or an interactive prompt before writing to a `/dev/sdX` block device. The
   script refuses `/dev/sda`.
5. **Copy the SystemRescue ISO** to the start of the target. The ISO's
   isohybrid MBR is preserved so the image is bootable as-is.
6. **Append a writable FAT32 partition** after the ISO. For block devices this
   is via `parted` + `mkfs.vfat` + mount + `cp`. For sparse-file output we
   use `mtools` (`mcopy`) directly so no `sudo`/loop-mount is needed — handy
   for CI where sudo isn't always clean.
7. **Drop on the FAT32 partition:**
   - `autorun/` (the test harness — autorun0 + tests/*)
   - `default.env` (env vars for autorun)
   - `sysrescue.yaml` (rendered from `config/sysrescue.yaml.template`; tells
     SystemRescue's autorun mechanism where to find scripts and to skip the
     keypress prompt)
   - `.simsys-rescue` (marker file used by `autorun0` to find this partition
     at boot, and by `bin/collect-results.sh` to find it after the run)

## `build-memtest-usb.sh` flow

1. **Download** Memtest86+ upstream `.usb.zip` from `memtest.org` at the
   pinned version.
2. **Verify SHA256** against a hardcoded expected value (placeholder in the
   script — fill in on first build, refresh on version bump). No GPG-signed
   manifest exists upstream.
3. **Extract** the `.img` from inside the zip.
4. **Write** to target (block device via `dd`, file via `cp`).

## CI pipeline (`.github/workflows/release.yml`)

Tag-triggered (`push: tags: ['v*']`). Steps:

1. Install build deps (`apt-get install dosfstools parted mtools xz-utils gpg`).
2. Run both build scripts with `--output dist/*.img`.
3. `xz -9 -T0` compress (saves ~70%).
4. SHA256 manifest.
5. `actions/attest-build-provenance` for SLSA provenance.
6. `softprops/action-gh-release` uploads the `.img.xz` files + `SHA256SUMS`.

## Adding a new test

`autorun/tests/<NN>-<name>.sh` — see [`CONTRIBUTING.md`](../CONTRIBUTING.md)
for naming conventions and the `lib.sh` helpers you should source.

## Bumping the upstream versions

- SystemRescue: bump `SYSRESCUE_VERSION` in `bin/build-rescue-usb.sh`. The
  GPG fingerprint is project-wide and stable across releases — no change.
- Memtest86+: bump `MEMTEST_VERSION` and update the `expected_sha` case
  branch with the new SHA256. Test the build, commit.
