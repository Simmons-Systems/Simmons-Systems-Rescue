#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../autorun/wipe-lib.sh"
}

@test "nist_method_for_type: nvme-ssd" {
    run nist_method_for_type "nvme-ssd"
    [ "$status" -eq 0 ]
    [ "$output" = "Purge|Block Erase" ]
}

@test "nist_method_for_type: nvme-ssd-sed" {
    run nist_method_for_type "nvme-ssd-sed"
    [ "$status" -eq 0 ]
    [ "$output" = "Purge|Crypto Erase" ]
}

@test "nist_method_for_type: sata-ssd" {
    run nist_method_for_type "sata-ssd"
    [ "$status" -eq 0 ]
    [ "$output" = "Purge|ATA Secure Erase Enhanced" ]
}

@test "nist_method_for_type: sata-ssd-sed" {
    run nist_method_for_type "sata-ssd-sed"
    [ "$status" -eq 0 ]
    [ "$output" = "Purge|Crypto Erase" ]
}

@test "nist_method_for_type: hdd" {
    run nist_method_for_type "hdd"
    [ "$status" -eq 0 ]
    [ "$output" = "Purge|Random overwrite + verify" ]
}

@test "nist_method_for_type: usb-flash" {
    run nist_method_for_type "usb-flash"
    [ "$status" -eq 0 ]
    [ "$output" = "Clear|Random overwrite (best-effort)" ]
}

@test "nist_method_for_type: fallback (unknown type)" {
    run nist_method_for_type "unknown-type"
    [ "$status" -eq 0 ]
    [ "$output" = "Clear|Random overwrite (fallback)" ]
}

@test "nist_method_for_type: fallback (empty)" {
    run nist_method_for_type ""
    [ "$status" -eq 0 ]
    [ "$output" = "Clear|Random overwrite (fallback)" ]
}
