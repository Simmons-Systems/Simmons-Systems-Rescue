# Results file format

Each autorun run produces one file at `results/results-<hostname>-<UTC-timestamp>.txt`
on the FAT32 partition of the rescue stick. The format is plain text,
grep-friendly, deliberately not JSON — humans read these.

## Anatomy

```
Simmons-Systems-Rescue autorun
Timestamp (UTC): 2026-05-08T18:00:00Z
Hostname:        nuc-test-01
Kernel:          6.6.x-rescue
STRESS_DURATION_SEC: 7200
MEMTESTER_PCT:       95


=== 10-inventory ===
=== system / baseboard ===
... dmidecode output ...
=== CPU ===
... lscpu output ...
=== memory (dmidecode) ===
... per-DIMM info ...
=== memory (free -h) ===
=== storage ===
=== PCI ===
=== USB ===
=== network interfaces ===
=== lshw -short ===
PASS: 10-inventory


=== 20-smart ===
... per-drive smartctl -a ...
PASS: 20-smart    (or FAIL: 20-smart exited 1)


=== 30-memtester ===
=== memtester 14848M 1 ===
[2026-05-08T18:01:00Z] Testing 14848MB (95% of MemAvailable)
... memtester per-test output ...
PASS: 30-memtester


=== 40-stress-ng ===
=== stress-ng --cpu 4 --vm 2 --hdd 1 --metrics --timeout 7200s ===
... stress-ng output ...
PASS: 40-stress-ng


=== 50-network ===
=== interface eno1 ===
... ethtool / ip addr ...
PASS: 50-network


=== OVERALL ===
OVERALL: PASS
```

## Quick-look greps

```bash
grep -E '^OVERALL:' results-*.txt           # one-line per box pass/fail
grep -E '^FAIL:'    results-*.txt           # which test(s) failed
grep -E 'SMART status'  results-*.txt       # all SMART summaries
grep -E 'errors'  results-*.txt | grep -i memtest    # spot-check memtester
```

## Per-section meaning

| Section | What you're looking for | What "bad" looks like |
|---------|-------------------------|------------------------|
| `10-inventory` | Sanity-check of CPU, RAM size, drive model/serial against the box's spec sheet. Always exits 0. | Missing DIMMs (slot listed `No Module Installed` when there should be one), wrong drive model. |
| `20-smart` | Per-drive overall SMART health. Exits non-zero if any drive reports `result: FAILED`. | Reallocated sectors, current pending sectors, "FAILED" overall status. |
| `30-memtester` | One pass of memtester across ~95% of MemAvailable. Exits non-zero on any error. | Bit pattern mismatches, "FAILURE" lines. |
| `40-stress-ng` | 2-hour combined CPU + memory + IO load. Exits non-zero if any worker bailed. | Errors counted in the metrics summary > 0; box rebooted mid-run (file is truncated). |
| `50-network` | Informational only. Always exits 0. | Wrong-speed link, unexpected interface count. |

## When you need more detail

The full output is in the same file — these are just the grep cheatcodes.
Open the file, scroll to the failing section, read upward for context.
