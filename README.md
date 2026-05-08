# Simmons-Systems-Rescue

Turnkey USB-based hardware burn-in kit. Plug it in, power on, walk away — get a
results file the next time you check.

Built originally for refurbishing Intel NUCs, but works on any x86_64 box that
boots from USB.

## What's in the box

The kit ships **two USB images**:

| USB | Purpose | Boots under stock Secure Boot? | Walk-away? |
|-----|---------|-------------------------------|------------|
| `rescue.img` | SystemRescue + autorun: 2-hour stress test, `memtester` (~95% of RAM), `smartctl` per drive, full hardware inventory, auto-poweroff | Yes (signed shim) | Yes |
| `memtest.img` | Memtest86+ (open source) for true bare-metal RAM testing | No — disable Secure Boot once in BIOS | Not yet — runs continuously, requires monitor (Phase 2 ships a fork with auto-halt) |

## Quick start

```bash
# Build both USB images locally
./bin/build-rescue-usb.sh /dev/sdX     # interactive confirmation; refuses /dev/sda
./bin/build-memtest-usb.sh /dev/sdY

# Or grab the latest release
gh release download --repo Simmons-Systems/Simmons-Systems-Rescue --pattern '*.img.xz'
xz -d rescue.img.xz && sudo dd if=rescue.img of=/dev/sdX bs=4M status=progress
```

Workflow per box:

1. Plug `rescue.img` USB into the box.
2. Power on. Walk away. ~2 hours later it powers itself off.
3. Pull the USB; on your dev box run `./bin/collect-results.sh /dev/sdX` to read the results file.
4. (Optional, if you want full RAM testing) Plug `memtest.img` USB, power on with monitor attached, run overnight.

## Documentation

- [`docs/usage.md`](docs/usage.md) — full walkthrough including BIOS prep
- [`docs/secure-boot.md`](docs/secure-boot.md) — how to disable Secure Boot for the Memtest USB
- [`docs/results-format.md`](docs/results-format.md) — what's in `results-*.txt` and how to interpret it
- [`docs/building-from-source.md`](docs/building-from-source.md) — how `bin/build-*.sh` work
- [`docs/adr/`](docs/adr/) — architecture decision records (two-USB rationale, Memtest fork roadmap, etc.)

## Roadmap

- **Phase 1 (here)**: SystemRescue+autorun walk-away USB, Memtest86+ stock USB, GitHub Actions release pipeline.
- **Phase 2**: Fork Memtest86+ to add `mt86p.cfg` config-file support, `NUMPASS` halt, and ACPI auto-poweroff so the Memtest USB is also walk-away.

## License

MIT — see [LICENSE](LICENSE).

Bundled SystemRescue ISO is GPLv3 (redistributed; source at [https://gitlab.com/systemrescue](https://gitlab.com/systemrescue)).
Bundled Memtest86+ binary is GPLv2 (source at [https://github.com/memtest86plus/memtest86plus](https://github.com/memtest86plus/memtest86plus)).
