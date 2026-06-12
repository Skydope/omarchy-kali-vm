# lib/debug.sh — debug mode state and functions.
# Extracted from original bin/omarchy-kali-vm. No logic changes.

DEBUG_MODE=false
DEBUG_SUBCOMMAND=""
DEBUG_REPORT_DIR=""
DEBUG_STAGE="setup"
DEBUG_STATUS="pending"
DEBUG_MESSAGE=""
DEBUG_IMAGE_ACTION="not-applicable"
DEBUG_PRESERVED_ARTIFACTS=()
DEBUG_URLS=()

record_debug_url() {
  local url="$1"

  if [[ "$DEBUG_MODE" != true ]] || [[ -z "$url" ]]; then
    return 0
  fi

  DEBUG_URLS+=("$url")
}

record_preserved_artifact() {
  local artifact_path="$1"

  if [[ "$DEBUG_MODE" != true ]] || [[ -z "$artifact_path" ]]; then
    return 0
  fi

  DEBUG_PRESERVED_ARTIFACTS+=("$artifact_path")
}

ensure_debug_report_dir() {
  if [[ "$DEBUG_MODE" != true ]] || [[ -n "$DEBUG_REPORT_DIR" ]]; then
    return 0
  fi

  local timestamp
  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  DEBUG_REPORT_DIR="$STATE_ROOT/${DEBUG_SUBCOMMAND}-${timestamp}"
  mkdir -p "$DEBUG_REPORT_DIR"
}

write_debug_report() {
  if [[ "$DEBUG_MODE" != true ]]; then
    return 0
  fi

  ensure_debug_report_dir

  {
    printf 'subcommand: %s\n' "$DEBUG_SUBCOMMAND"
    printf 'debug: true\n'
    printf 'timestamp: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'status: %s\n' "$DEBUG_STATUS"
    printf 'stage: %s\n' "$DEBUG_STAGE"
    printf 'message: %s\n' "${DEBUG_MESSAGE:-none}"
    printf 'report_dir: %s\n' "$DEBUG_REPORT_DIR"
    printf 'compose_file: %s\n' "$COMPOSE_FILE"
    printf 'config_dir: %s\n' "$KALI_CONFIG_DIR"
    printf 'storage_dir: %s\n' "$KALI_STORAGE"
    printf 'shared_dir: %s\n' "$KALI_SHARED_DIR"
    printf 'runtime_launcher: %s\n' "$RUNTIME_DESKTOP_FILE"
    printf 'docker_image_action: %s\n' "$DEBUG_IMAGE_ACTION"
    printf '\nurls:\n'
    if (( ${#DEBUG_URLS[@]} == 0 )); then
      printf '  (none)\n'
    else
      printf '  %s\n' "${DEBUG_URLS[@]}"
    fi
    printf '\npreserved_artifacts:\n'
    if (( ${#DEBUG_PRESERVED_ARTIFACTS[@]} == 0 )); then
      printf '  (none)\n'
    else
      printf '  %s\n' "${DEBUG_PRESERVED_ARTIFACTS[@]}"
    fi
  } > "$DEBUG_REPORT_DIR/report.txt"
}

print_debug_summary() {
  if [[ "$DEBUG_MODE" != true ]]; then
    return 0
  fi

  echo "Debug report written to: $DEBUG_REPORT_DIR"
  if (( ${#DEBUG_PRESERVED_ARTIFACTS[@]} > 0 )); then
    echo "Preserved artifacts:"
    printf '  %s\n' "${DEBUG_PRESERVED_ARTIFACTS[@]}"
  fi
}

prepare_debug_run() {
  local subcommand="$1"

  DEBUG_MODE=true
  DEBUG_SUBCOMMAND="$subcommand"
  DEBUG_REPORT_DIR=""
  DEBUG_STAGE="setup"
  DEBUG_STATUS="running"
  DEBUG_MESSAGE=""
  DEBUG_IMAGE_ACTION="not-applicable"
  DEBUG_PRESERVED_ARTIFACTS=()
  DEBUG_URLS=()

  ensure_debug_report_dir
  echo "Debug mode enabled."
  echo "Reports will be written under: $DEBUG_REPORT_DIR"
}

capture_debug_sidecar() {
  local source_path="$1"
  local dest_name="$2"

  if [[ "$DEBUG_MODE" != true ]] || [[ ! -f "$source_path" ]]; then
    return 0
  fi

  ensure_debug_report_dir
  cp -f "$source_path" "$DEBUG_REPORT_DIR/$dest_name"
  record_preserved_artifact "$DEBUG_REPORT_DIR/$dest_name"
}

snapshot_archive_stats() {
  local archive_glob="$1"
  local archive_path
  local archive_paths=()

  if [[ "$DEBUG_MODE" != true ]]; then
    return 0
  fi

  ensure_debug_report_dir
  : > "$DEBUG_REPORT_DIR/archive.stat"
  mapfile -t archive_paths < <(compgen -G "$archive_glob" || true)
  for archive_path in "${archive_paths[@]}"; do
    printf '%s\t%s bytes\n' "$archive_path" "$(stat -c%s "$archive_path" 2>/dev/null || echo unknown)" >> "$DEBUG_REPORT_DIR/archive.stat"
  done

  if [[ -s "$DEBUG_REPORT_DIR/archive.stat" ]]; then
    record_preserved_artifact "$DEBUG_REPORT_DIR/archive.stat"
  else
    rm -f "$DEBUG_REPORT_DIR/archive.stat"
  fi
}

preserve_install_debug_artifacts() {
  local archive_path

  if [[ "$DEBUG_MODE" != true ]]; then
    return 0
  fi

  shopt -s nullglob
  for archive_path in "$KALI_STORAGE"/*.7z; do
    record_preserved_artifact "$archive_path"
  done
  shopt -u nullglob

  capture_debug_sidecar "$KALI_STORAGE/SHA256SUMS" "SHA256SUMS"
  capture_debug_sidecar "$KALI_STORAGE/SHA256SUMS.gpg" "SHA256SUMS.gpg"
  snapshot_archive_stats "$KALI_STORAGE/*.7z"
}

fail_install() {
  local stage="$1"
  local message="$2"

  DEBUG_STAGE="$stage"
  DEBUG_STATUS="failed"
  DEBUG_MESSAGE="$message"
  preserve_install_debug_artifacts
  write_debug_report
  echo "ERROR: $message"
  print_debug_summary
  exit 1
}

preserve_remove_debug_artifacts() {
  local archive_path
  local archive_name

  if [[ "$DEBUG_MODE" != true ]]; then
    return 0
  fi

  shopt -s nullglob
  for archive_path in "$KALI_STORAGE"/*.7z; do
    archive_name=$(basename "$archive_path")
    mv "$archive_path" "$DEBUG_REPORT_DIR/$archive_name"
    record_preserved_artifact "$DEBUG_REPORT_DIR/$archive_name"
  done
  shopt -u nullglob
  snapshot_archive_stats "$DEBUG_REPORT_DIR/*.7z"
}
