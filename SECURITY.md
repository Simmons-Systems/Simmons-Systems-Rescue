# Security Policy

## Supported versions

Only the latest release tag is supported. Fixes will land on `main` and be
cut as a new patch release; older tags will not be back-patched.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems.

Email **Avicennasis@gmail.com** with:

- A description of the issue.
- Steps to reproduce (or a proof-of-concept).
- The version or commit SHA you found it against.
- Any suggested mitigation if you have one.

Expect an acknowledgement within a week. This is a side-project — there is
no bug bounty and no SLA — but security issues are taken seriously and a
fix and disclosure will be coordinated with you.

## Threat model (kit-specific)

The kit produces USB images intended to be run **on hardware you control,
during a burn-in / refurbishment workflow**. Particular concerns to flag:

- **Build-script supply chain.** `bin/build-rescue-usb.sh` and `build-memtest-usb.sh`
  download upstream images (SystemRescue ISO, Memtest86+ binary) at build time.
  Both scripts verify upstream signatures / checksums before flashing — if you
  see a checksum mismatch, **do not** continue; report it.
- **`dd` to wrong device.** The build scripts refuse `/dev/sda` and require
  interactive confirmation, but they are still capable of overwriting any
  block device. Read the prompt before typing `yes`.
- **Results files are written to a writable FAT32 partition** on the rescue
  USB. If you use the same stick on multiple boxes the partition accumulates
  results — there is no encryption. Treat results files as containing
  hardware inventory information (serials, MAC addresses) and dispose of them
  accordingly.

## Out of scope

- Issues in upstream dependencies (report upstream — SystemRescue at
  [gitlab.com/systemrescue](https://gitlab.com/systemrescue), Memtest86+ at
  [github.com/memtest86plus/memtest86plus](https://github.com/memtest86plus/memtest86plus)).
- Hardware-level attacks against firmware/BIOS that the kit cannot detect.
- Misconfiguration by consumers of this project.
