# Changelog

All notable changes to `Simmons-Systems-Rescue` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project scaffolding.
- SystemRescue+autorun harness (`autorun/`): inventory, SMART, memtester, stress-ng, network checks.
- USB build scripts (`bin/build-rescue-usb.sh`, `bin/build-memtest-usb.sh`).
- Results collection helper (`bin/collect-results.sh`).
- Documentation: usage, Secure Boot prep, results format, build-from-source, ADRs.
- GitHub Actions release pipeline producing `rescue.img.xz` and `memtest.img.xz` on tag push.
- NIST 800-88 disk-wipe USB: `bin/build-wipe-usb.sh` plus `autorun/wipe-lib.sh`, Wizard (interactive) and eWaste (auto) boot modes with JSON audit logs.

### Fixed
- Docs: corrected stale Memtest86+ packaging description (`.usb.zip` → hybrid `.iso.zip`), removed dangling `CONTRIBUTING.md` reference, and updated README quick-start wording to cover all three USB images.
