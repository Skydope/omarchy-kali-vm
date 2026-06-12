# lib/download.sh — Kali QCOW2 download, verification, and extraction.
# Extracted from original bin/omarchy-kali-vm with GPG fingerprint pinning added.
# Requires lib/config.sh, lib/debug.sh sourced first.

resolve_current_kali_qcow2_archive() {
  curl -fsSL https://cdimage.kali.org/kali-images/current/ | grep -o 'kali-linux-[^"<>]*-qemu-amd64\.7z' | head -1
}

download_kali_qcow2() {
  local QCOW2="$KALI_STORAGE/data.qcow2"
  local SOURCE_LABEL="${1:-weekly}"

  if [[ -f "$QCOW2" ]]; then
    echo "Kali QCOW2 image already downloaded, skipping."
    return 0
  fi

  local KALI_BASE_URL KALI_URL DOWNLOAD_FILENAME DOWNLOAD_FILE
  if [[ $SOURCE_LABEL == "weekly" ]]; then
    local KALI_YEAR KALI_WEEK
    KALI_BASE_URL="https://cdimage.kali.org/kali-images/kali-weekly"
    KALI_YEAR=$(date +%Y)
    KALI_WEEK=$(date +%V)
    KALI_URL="${KALI_BASE_URL}/kali-linux-${KALI_YEAR}-W${KALI_WEEK}-qemu-amd64.7z"
  else
    local CURRENT_ARCHIVE
    KALI_BASE_URL="https://cdimage.kali.org/kali-images/current"
    CURRENT_ARCHIVE=$(resolve_current_kali_qcow2_archive)
    if [[ -z "$CURRENT_ARCHIVE" ]]; then
      if [[ "$DEBUG_MODE" = true ]]; then
        fail_install "download" "Could not determine the latest current Kali QEMU archive."
      fi
      echo "ERROR: Could not determine the latest current Kali QEMU archive."
      return 1
    fi
    KALI_URL="${KALI_BASE_URL}/${CURRENT_ARCHIVE}"
  fi
  DOWNLOAD_FILENAME="${KALI_URL##*/}"
  DOWNLOAD_FILE="$KALI_STORAGE/$DOWNLOAD_FILENAME"
  record_debug_url "$KALI_URL"

  echo "Downloading Kali QCOW2 image ($SOURCE_LABEL)..."
  echo "URL: $KALI_URL"

  DEBUG_STAGE="download"
  curl -fL --retry 2 --retry-delay 5 -C - -o "$DOWNLOAD_FILE" "$KALI_URL" || {
    if [[ "$DEBUG_MODE" = true ]]; then
      fail_install "download" "Failed to download Kali QCOW2 archive."
    fi
    echo "ERROR: Failed to download Kali QCOW2 archive."
    rm -f "$DOWNLOAD_FILE"
    return 1
  }

  echo "Verifying download integrity..."
  DEBUG_STAGE="verify"
  local GNUPG_TMP
  GNUPG_TMP=$(mktemp -d)
  curl -fsSL -o "$GNUPG_TMP/kali-key.asc" https://archive.kali.org/archive-key.asc || {
    rm -rf "$GNUPG_TMP"
    if [[ "$DEBUG_MODE" = true ]]; then
      fail_install "verify" "Failed to download Kali archive signing key."
    fi
    echo "ERROR: Failed to download Kali archive signing key."
    rm -f "$DOWNLOAD_FILE"
    return 1
  }
  record_debug_url "https://archive.kali.org/archive-key.asc"
  echo "Importing Kali archive signing key..."
  if ! gpg --homedir "$GNUPG_TMP" --import "$GNUPG_TMP/kali-key.asc"; then
    rm -rf "$GNUPG_TMP"
    if [[ "$DEBUG_MODE" = true ]]; then
      fail_install "verify" "Failed to import Kali archive signing key."
    fi
    echo "ERROR: Failed to import Kali archive signing key."
    rm -f "$DOWNLOAD_FILE" "$KALI_STORAGE/SHA256SUMS" "$KALI_STORAGE/SHA256SUMS.gpg"
    return 1
  fi

  curl -fsSL -o "$KALI_STORAGE/SHA256SUMS" "${KALI_BASE_URL}/SHA256SUMS" || {
    rm -rf "$GNUPG_TMP"
    record_debug_url "${KALI_BASE_URL}/SHA256SUMS"
    if [[ "$DEBUG_MODE" = true ]]; then
      fail_install "verify" "Failed to download Kali checksum file."
    fi
    echo "ERROR: Failed to download Kali checksum file."
    rm -f "$DOWNLOAD_FILE" "$KALI_STORAGE/SHA256SUMS" "$KALI_STORAGE/SHA256SUMS.gpg"
    return 1
  }
  record_debug_url "${KALI_BASE_URL}/SHA256SUMS"
  curl -fsSL -o "$KALI_STORAGE/SHA256SUMS.gpg" "${KALI_BASE_URL}/SHA256SUMS.gpg" || {
    rm -rf "$GNUPG_TMP"
    record_debug_url "${KALI_BASE_URL}/SHA256SUMS.gpg"
    if [[ "$DEBUG_MODE" = true ]]; then
      fail_install "verify" "Failed to download Kali checksum signature."
    fi
    echo "ERROR: Failed to download Kali checksum signature."
    rm -f "$DOWNLOAD_FILE" "$KALI_STORAGE/SHA256SUMS" "$KALI_STORAGE/SHA256SUMS.gpg"
    return 1
  }
  record_debug_url "${KALI_BASE_URL}/SHA256SUMS.gpg"

  # Single GPG verification with --status-fd + allowlist fingerprint check.
  # Replaces the original TOFU approach that trusted any key in the keyring.
  # Exit code is checked explicitly — command substitution with set -e is fragile.
  echo "Verifying SHA256SUMS signature..."
  local gpg_status
  gpg_status=$(gpg --homedir "$GNUPG_TMP" --status-fd 1 \
      --verify "$KALI_STORAGE/SHA256SUMS.gpg" "$KALI_STORAGE/SHA256SUMS" 2>/dev/null) || {
    rm -rf "$GNUPG_TMP"
    if [[ "$DEBUG_MODE" = true ]]; then
      fail_install "verify" "GPG signature verification failed. The checksum file may have been tampered with."
    fi
    echo "ERROR: GPG signature verification failed! The checksum file may have been tampered with."
    rm -f "$DOWNLOAD_FILE" "$KALI_STORAGE/SHA256SUMS" "$KALI_STORAGE/SHA256SUMS.gpg"
    return 1
  }

  # VALIDSIG: the last field ($NF) is the primary key fingerprint.
  # Even if Kali signs with a subkey, $NF is always the primary — matches the allowlist.
  local SIGNER_FPR
  SIGNER_FPR=$(awk '/^\[GNUPG:\] VALIDSIG/ {print $NF; exit}' <<< "$gpg_status")

  if [[ -z "$SIGNER_FPR" ]]; then
    rm -rf "$GNUPG_TMP"
    echo "FATAL: No se pudo determinar el fingerprint del firmante" >&2
    rm -f "$DOWNLOAD_FILE" "$KALI_STORAGE/SHA256SUMS" "$KALI_STORAGE/SHA256SUMS.gpg"
    return 1
  fi

  local ok=false
  for fpr in "${KALI_ALLOWED_FINGERPRINTS[@]}"; do
    [[ "$SIGNER_FPR" == "$fpr" ]] && { ok=true; break; }
  done
  if [[ "$ok" != true ]]; then
    rm -rf "$GNUPG_TMP"
    echo "FATAL: SHA256SUMS firmado por key no confiable: $SIGNER_FPR" >&2
    rm -f "$DOWNLOAD_FILE" "$KALI_STORAGE/SHA256SUMS" "$KALI_STORAGE/SHA256SUMS.gpg"
    return 1
  fi
  echo "GPG signature verified (key: ${SIGNER_FPR:0:16}...)"
  rm -rf "$GNUPG_TMP"

  # Verify SHA256 checksum
  local EXPECTED_SUM ACTUAL_SUM
  EXPECTED_SUM=$(awk -v file="$DOWNLOAD_FILENAME" '$2 == file {print $1; exit}' "$KALI_STORAGE/SHA256SUMS")
  if [[ -z "$EXPECTED_SUM" ]]; then
    if [[ "$DEBUG_MODE" = true ]]; then
      fail_install "verify" "No checksum found for $DOWNLOAD_FILENAME in SHA256SUMS."
    fi
    echo "ERROR: No checksum found for $DOWNLOAD_FILENAME in SHA256SUMS"
    rm -f "$DOWNLOAD_FILE" "$KALI_STORAGE/SHA256SUMS" "$KALI_STORAGE/SHA256SUMS.gpg"
    return 1
  fi

  ACTUAL_SUM=$(sha256sum "$DOWNLOAD_FILE" | awk '{print $1}')
  echo "Expected SHA256: $EXPECTED_SUM"
  echo "Actual SHA256:   $ACTUAL_SUM"
  if [[ "$ACTUAL_SUM" != "$EXPECTED_SUM" ]]; then
    if [[ "$DEBUG_MODE" = true ]]; then
      fail_install "verify" "SHA256 checksum mismatch."
    fi
    echo "ERROR: SHA256 checksum mismatch!"
    rm -f "$DOWNLOAD_FILE" "$KALI_STORAGE/SHA256SUMS" "$KALI_STORAGE/SHA256SUMS.gpg"
    return 1
  fi
  echo "SHA256 checksum verified."
  if [[ "$DEBUG_MODE" != true ]]; then
    rm -f "$KALI_STORAGE/SHA256SUMS" "$KALI_STORAGE/SHA256SUMS.gpg"
  fi

  # Extract the QCOW2 on the host — no Docker dependency for installation.
  echo "Extracting QCOW2 from 7z archive..."
  DEBUG_STAGE="extract"
  7z x -y -o"$KALI_STORAGE" "$DOWNLOAD_FILE" > /dev/null || {
    if [[ $SOURCE_LABEL == "weekly" ]]; then
      echo "Weekly Kali archive verified but failed to extract. Falling back to the latest current release..."
      echo "Archive: $DOWNLOAD_FILE"
      echo "Archive size: $(stat -c%s "$DOWNLOAD_FILE" 2>/dev/null || echo unknown) bytes"
      download_kali_qcow2 current
      return $?
    fi
    if [[ "$DEBUG_MODE" = true ]]; then
      fail_install "extract" "Failed to extract QCOW2 archive."
    fi
    echo "ERROR: Failed to extract QCOW2 archive."
    echo "Archive: $DOWNLOAD_FILE"
    echo "Archive size: $(stat -c%s "$DOWNLOAD_FILE" 2>/dev/null || echo unknown) bytes"
    rm -f "$DOWNLOAD_FILE"
    return 1
  }
  local EXTRACTED
  EXTRACTED=$(find "$KALI_STORAGE" -maxdepth 1 -name "*.qcow2" ! -name "data.qcow2" | head -1)
  if [[ -n "$EXTRACTED" ]]; then
    mv "$EXTRACTED" "$QCOW2"
  else
    if [[ "$DEBUG_MODE" = true ]]; then
      fail_install "extract" "No QCOW2 file found after extraction."
    fi
    echo "ERROR: No QCOW2 file found after extraction"
    rm -f "$DOWNLOAD_FILE"
    return 1
  fi

  chattr +C "$QCOW2" 2>/dev/null || true

  echo "Download complete."
  echo "Preserved archive: $DOWNLOAD_FILE"
}
