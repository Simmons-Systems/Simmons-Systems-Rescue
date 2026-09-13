#!/bin/bash
# Shared SystemRescue ISO download + signature verification for the USB build
# scripts. Requires the caller to define:
#   iso_path, sig_path,
#   SYSRESCUE_VERSION, SYSRESCUE_ISO_URL, SYSRESCUE_SIG_URL, SYSRESCUE_SIGNING_KEY

download_iso() {
    if [[ -f "$iso_path" ]]; then
        echo "==> Using cached ISO: $iso_path"
    else
        echo "==> Downloading SystemRescue ${SYSRESCUE_VERSION}..."
        curl -fL --retry 3 -o "$iso_path" "$SYSRESCUE_ISO_URL"
    fi
    if [[ ! -f "$sig_path" ]]; then
        curl -fL --retry 3 -o "$sig_path" "$SYSRESCUE_SIG_URL"
    fi
    echo "==> Verifying signature..."
    # Import key if missing, then verify
    if ! gpg --list-keys "$SYSRESCUE_SIGNING_KEY" > /dev/null 2>&1; then
        gpg --keyserver keyserver.ubuntu.com --recv-keys "$SYSRESCUE_SIGNING_KEY" \
            || gpg --keyserver keys.openpgp.org --recv-keys "$SYSRESCUE_SIGNING_KEY"
    fi
    gpg --verify "$sig_path" "$iso_path"
}
