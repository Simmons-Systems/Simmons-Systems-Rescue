# ADR 0001 — Ship two USBs, not one

Date: 2026-05-08
Status: Accepted

## Context

The kit needs to run both Memtest86+ (true bare-metal RAM testing) and
SystemRescue (everything-else burn-in). The natural question: one USB with a
GRUB menu, or two separate sticks?

## Considered

1. **Single USB via Ventoy.** Ventoy supports putting both an ISO and an IMG
   on one stick with a GRUB2 menu, and it added Secure-Boot support in 1.0.07.
   But Ventoy's bootloader itself is **not** Microsoft-signed — first boot on
   a stock Secure-Boot box prompts for one-time MOK key enrollment via
   shim/MokManager. That manual step is fatal to a "plug in, walk away"
   workflow on the first run. (Subsequent runs of the same stick on the same
   box are zero-touch.)
2. **Single USB via hand-rolled GRUB2 multiboot.** Possible but disables
   Secure Boot entirely (we'd be loading our own unsigned GRUB) — same MOK
   problem, plus we own the boot chain.
3. **Two separate signed USBs.** SystemRescue 13.00 ships a signed shim that
   boots clean under stock Secure Boot. Memtest86+ stock requires Secure
   Boot disabled in BIOS once per box (documented; the box stays disabled
   for the duration of refurb anyway).

## Decision

**Two USBs, not one.** The first-run friction of Ventoy MOK enrollment
defeats the kit's reason for existing. Two sticks is mildly annoying
logistically but every step from "plug in" onward is zero-touch.

## Consequences

- Build pipeline produces two images: `rescue.img` and `memtest.img`.
- Memtest stage requires a one-time BIOS Secure-Boot toggle per box — covered
  in `docs/secure-boot.md`.
- If we ever ship the Phase-2 Simmons-Systems Memtest fork with a
  Microsoft-signed shim, we could revisit single-USB Ventoy at that point.
