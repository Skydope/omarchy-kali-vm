# lib/state.sh — managed state detection, .desktop launcher, and desktop database.
# Extracted from original bin/omarchy-kali-vm. Requires lib/config.sh sourced first.

refresh_desktop_database() {
  if ! command -v update-desktop-database >/dev/null 2>&1; then
    return 0
  fi

  update-desktop-database "$USER_APPLICATIONS_DIR" >/dev/null 2>&1 || true
}

write_runtime_launcher() {
  mkdir -p "$USER_APPLICATIONS_DIR"

  cat > "$RUNTIME_DESKTOP_FILE" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Kali
Comment=Launch the packaged Kali Linux virtual machine
Exec=omarchy-kali-vm launch
Icon=omarchy-kali-vm
Terminal=false
Categories=System;Security;Utility;
Keywords=kali;virtual machine;vm;security;
EOF

  refresh_desktop_database
}

remove_runtime_launcher() {
  rm -f "$RUNTIME_DESKTOP_FILE"
  refresh_desktop_database
}

list_managed_state_paths() {
  printf '%s\n' \
    "$KALI_CONFIG_DIR" \
    "$COMPOSE_FILE" \
    "$KALI_STORAGE" \
    "$KALI_SHARED_DIR" \
    "$RUNTIME_DESKTOP_FILE"
}

list_existing_managed_state_paths() {
  local managed_path

  while IFS= read -r managed_path; do
    if [[ -e "$managed_path" ]]; then
      printf '%s\n' "$managed_path"
    fi
  done < <(list_managed_state_paths)
}

managed_state_exists() {
  local existing_state

  while IFS= read -r existing_state; do
    if [[ -n "$existing_state" ]]; then
      return 0
    fi
  done < <(list_existing_managed_state_paths)

  return 1
}
