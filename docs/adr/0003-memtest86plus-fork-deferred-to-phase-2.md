# ADR 0003 — Defer the Memtest86+ fork to Phase 2

Date: 2026-05-08
Status: Accepted

## Context

True walk-away Memtest is the obvious next-step ambition: plug in the Memtest
USB, power on, walk away, come back to a results file with auto-poweroff. This
needs:

1. Config-file support so number-of-passes and error-thresholds are
   declarative.
2. ACPI poweroff (Memtest86+ runs bare-metal, not under Linux, so it's not
   `poweroff` — has to call ACPI S5 directly).
3. Report-write to FAT32 from bare metal (already partially supported in
   Memtest86+ v6+ for BadRAM patterns; needs extension).

Memtest86+ is GPLv2 and the source is at
[github.com/memtest86plus/memtest86plus](https://github.com/memtest86plus/memtest86plus),
so a fork is feasible. PassMark Memtest86 has had these features for years
but it's proprietary.

## Decision

Defer the fork to Phase 2. Phase 1 ships stock Memtest86+ on the Memtest USB
with the documented "needs a monitor for now" caveat.

## Why deferred

- Bare-metal C work in someone else's codebase is genuinely 1-2 weeks of
  focused effort, plus another week if we want the fork to be Microsoft-signed
  for Secure-Boot compatibility (Microsoft's open-source bootloader signing
  process is months-long).
- Phase 1 is already a complete kit without it — `memtester` inside
  SystemRescue catches the majority of memory faults that Phase 1 cares
  about.
- Doing the fork badly (e.g., flaky ACPI poweroff) is worse than not doing
  it.

## Phase 2 sketch

When we pick this up:

1. Fork upstream to `Simmons-Systems/memtest86plus`.
2. Add `mt86p.cfg` parser at the FAT32 partition root. Honor at minimum:
   `NUMPASS`, `EXITMODE` (`halt` / `poweroff` / `reboot`), `LOGFILE`.
3. Wire ACPI poweroff via `efi_set_variable` or `acpi_enter_sleep` — there's
   prior art in coreboot we can crib from.
4. Decide whether to pursue Microsoft-signed shim. Probably not for v1; we
   live with "Secure Boot off" on the BIOS for the foreseeable.
5. Substitute the new fork into `bin/build-memtest-usb.sh`. Update
   `docs/secure-boot.md` if the Secure-Boot story changes.
6. File a Redmine ticket against the `simmons-systems-rescue` project once
   Phase 1 ships, with a link back to this ADR.
