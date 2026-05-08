# Secure Boot prep for the Memtest USB

The Memtest86+ open-source binary is GPLv2 but **not Microsoft-signed**, so
NUCs (and most other modern x86 boxes) ship with Secure Boot configured to
reject it. This is a one-time per-box BIOS toggle.

The SystemRescue rescue stick is signed and **does not** require this — only
the Memtest USB does.

## Intel NUC (BNUCxx, NUC8, NUC10, NUC11, NUC12, NUC13)

1. Plug in keyboard + monitor. Power on, mash `F2` during the splash to enter
   the BIOS / Visual BIOS.
2. Find **Boot → Secure Boot** (exact path varies by NUC generation; on
   Visual BIOS it's under **Advanced → Boot → Secure Boot**).
3. Set **Secure Boot** to **Disabled**.
4. Save & exit (`F10`). Box reboots.
5. Boot the Memtest USB (mash `F10` for the boot menu, pick the USB).

## Other vendors

Same idea, different paths. Common variants:

| Vendor | BIOS key | Path |
|--------|----------|------|
| Dell | `F2` or `F12` (boot menu) | Boot Sequence → Secure Boot → Disabled |
| HP | `F10` | Boot Options → Secure Boot → Disabled |
| Lenovo ThinkCentre | `F1` | Security → Secure Boot → Disabled |
| ASRock NUC-class | `F2` | Security → Secure Boot → Disabled |

## Re-enabling Secure Boot afterward

If the box is going to a customer / production, flip Secure Boot back to
**Enabled** in the BIOS after the Memtest pass is done. The rescue stick
still works under Secure Boot enabled.

## Why we don't ship a signed Memtest

Two options were considered, both rejected for Phase 1:

- **PassMark Memtest86 Free** is Microsoft-signed but its license terms don't
  clearly grant redistribution rights, so we'd have to fetch it at build-time
  rather than ship it (Gentoo et al. handle it the same way). Free edition
  also can't be configured for unattended runs (config files are Pro-only).
- **Sign Memtest86+ ourselves** with a Simmons-Systems Microsoft-trusted
  shim. Possible but Microsoft's signing process for open-source bootloaders
  is months-long and not justified by Phase 1 scope.

Phase 2 is a Simmons-Systems fork of Memtest86+ that adds config-file +
auto-halt support; signing it for Secure Boot is a separate decision tracked
there.
