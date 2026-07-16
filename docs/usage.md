# Usage

End-to-end walkthrough. Allow ~2.5 hours per box.

## Prerequisites

- Two spare USB sticks (≥4GB each is plenty).
- A dev box (Linux) with `bash`, `curl`, `gpg`, `parted`, `dosfstools`,
  `mtools`, and `xz`. On Debian/Ubuntu: `sudo apt install dosfstools parted
  util-linux mtools xz-utils gpg curl`.
- The target box(es) you want to test (Intel NUCs, refurb desktops, etc.).

## Step 1 — Build (or download) the USB images

### Option A: build locally

```bash
git clone https://github.com/Simmons-Systems/Simmons-Systems-Rescue.git
cd Simmons-Systems-Rescue
./bin/build-rescue-usb.sh /dev/sdX     # interactive confirmation
./bin/build-memtest-usb.sh /dev/sdY
```

The build scripts download upstream SystemRescue + Memtest86+ on first run
and cache them in `.cache/`.

### Option B: download a release

```bash
gh release download --repo Simmons-Systems/Simmons-Systems-Rescue --pattern '*.img.xz'
xz -d rescue.img.xz memtest.img.xz
sudo dd if=rescue.img  of=/dev/sdX bs=4M conv=fsync status=progress
sudo dd if=memtest.img of=/dev/sdY bs=4M conv=fsync status=progress
sync
```

## Step 2 — Optional, for the Memtest USB only: disable Secure Boot

Memtest86+ is not Microsoft-signed, so stock Secure-Boot NUCs reject it.
See [`secure-boot.md`](secure-boot.md) for the BIOS toggles.

The SystemRescue rescue stick boots fine under stock Secure Boot; nothing to
do for it.

## Step 3 — Run the rescue stick (walk-away)

1. Plug `rescue.img` USB into the target box.
2. Power on. The box boots SystemRescue.
3. Autorun fires automatically — no keypress required.
4. Inventory + SMART + memtester + 2-hour stress + network checks run in
   sequence; results land in `results/results-<host>-<timestamp>.txt` on the
   FAT32 partition.
5. After tests complete, `poweroff` is called. The box turns itself off.
6. Pull the USB.

Total wallclock ≈ 2 hours 5 minutes by default. Tweak `STRESS_DURATION_SEC`
in `/default.env` on the FAT32 partition if you want shorter or longer.

## Step 4 — Read the results

On your dev box:

```bash
./bin/collect-results.sh /dev/sdX               # prints the latest results file
./bin/collect-results.sh --copy /dev/sdX        # also saves it under ~/nuc-burnin-results/
```

The results file is plain text — grep-friendly. Look for:

- `OVERALL: PASS` at the bottom — green light.
- `FAIL: ...` lines — point you at which test failed and roughly why.
- See [`results-format.md`](results-format.md) for the full schema.

## Step 5 — Optional: Memtest86+ overnight pass

For full RAM coverage (kernel + DMA buffers + page tables that `memtester`
can't touch):

1. Plug `memtest.img` USB.
2. Connect a monitor.
3. Power on. Memtest86+ launches and starts pass 1.
4. Leave it overnight. In the morning, count completed passes and check the
   error column.
5. Pull the USB. Move on.

> Phase 2 (tracked via Redmine) will replace this with a Simmons-Systems fork
> of Memtest86+ that adds `mt86p.cfg` config support, finite pass counts, and
> ACPI auto-poweroff so this stage is also walk-away.

## Wipe USB — overwrite pass count

Overwrite-based methods (HDD, USB flash, and the frozen-SSD fallback) default to
a **single** random-overwrite pass. This is compliant with NIST SP 800-88 Rev. 1
— a single pass is sufficient for modern media, and additional passes are **not
required**. SSD erase/crypto methods ignore this setting entirely.

If an organizational policy mandates stricter-than-NIST multi-pass overwrite
(e.g. legacy DoD 5220.22-M), raise the pass count via any of these — highest
precedence first:

1. **Environment variable** (scripted/direct runs): `WIPE_OVERWRITE_ROUNDS=3`
2. **Kernel cmdline** (per boot): add `ssr.overwrite-rounds=3` to the boot entry
3. **Baked default**: edit `WIPE_OVERWRITE_ROUNDS` in `/wipe.env` on the FAT32
   partition of the wipe stick (set at build time from `config/wipe.env`)

Only positive integers are accepted; an invalid value is ignored (with a warning)
and the next source is tried, so a bad value never silently reduces the pass
count. Each extra pass costs proportionally more wall-clock time. The pass count
actually used is recorded per drive in the JSON audit log as `overwrite_rounds`
(`null` for erase/crypto methods).

## Troubleshooting

- **Box didn't power off after 2.5h.** SystemRescue may have crashed mid-test.
  Cycle the power, plug the USB into your dev box, run `collect-results.sh`
  to see how far it got.
- **"No writable FAT32 partition found"** message in results — `build-rescue-usb.sh`
  didn't manage to add the writable partition. Re-flash from a fresh image.
- **NUC silently refuses to boot the Memtest USB** — Secure Boot is still on.
  See [`secure-boot.md`](secure-boot.md).
