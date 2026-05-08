# ADR 0002 — Use `memtester` inside SystemRescue, not PassMark Memtest86, for Phase 1

Date: 2026-05-08
Status: Accepted

## Context

The original instinct was to ship PassMark Memtest86 Free as the RAM-testing
stage. Investigation surfaced two blockers:

1. **PassMark Free is closed-source and its config-file mechanism is Pro-only.**
   The Free edition runs hardcoded defaults: it boots, executes ~4 passes of
   the standard test set, halts, and writes an HTML/log report to the FAT32
   partition. There's no way to tune pass count, error thresholds, or exit
   behavior without buying Pro (~$44 USD per seat).
2. **PassMark Free's redistribution rights are ambiguous.** The license-info
   page only says "free to download with no restrictions on usage" — it does
   not explicitly grant redistribution. Gentoo and Debian package it as a
   fetch-at-install rather than mirroring the binary. Conservative read: we
   shouldn't commit the binary to a public repo or ship it inside a public
   release artifact.

We wanted RAM testing in the walk-away SystemRescue stage anyway (separate
from the bare-metal Memtest USB), so we evaluated alternatives.

## Considered

1. **Buy PassMark Pro** for the Phase 1 release. Real money + per-seat
   licensing complicates the public-repo distribution story.
2. **Wrap PassMark Free with our own config layer.** Not possible — it's a
   closed-source bare-metal binary. There's nothing else running concurrently
   that could "control" it.
3. **Memtest86+ stock** as the RAM-testing stage. It IS GPLv2 and freely
   redistributable, but has no config-file or auto-halt either, and is not
   Microsoft-signed (Secure Boot conflict).
4. **`memtester` from inside SystemRescue's autorun.** A userland program that
   `malloc`s ~95% of MemAvailable and runs the standard Memtest pattern set.
   Catches the overwhelming majority of bad-stick failures (especially DOA
   cases). Misses kernel-space, DMA buffers, and page tables, which together
   are <5% of physical RAM on a modern Linux kernel.

## Decision

Phase 1 ships `memtester` inside the SystemRescue autorun harness as the
default RAM check. The dedicated Memtest86+ USB is shipped alongside as a
"plug in for the deeper overnight pass" supplementary stick — not the
primary walk-away path.

## Consequences

- Walk-away workflow tests ~95% of RAM in <5 minutes (memtester on a NUC
  with 16GB completes in ~3-4 minutes per round, usually).
- Boxes that pass the SystemRescue walk-away are ~99% confidently good. The
  Memtest USB is for the small remainder where you want full coverage.
- Phase 2 (forked Memtest86+ with config support) replaces the Memtest USB
  side; the SystemRescue side stays as is.
