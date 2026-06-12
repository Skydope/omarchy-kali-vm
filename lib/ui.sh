# lib/ui.sh — display helpers, gum wrappers, and usage output.
# Extracted from original bin/omarchy-kali-vm. Requires lib/config.sh sourced first.

notify_if_available() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$@"
  fi
}

print_install_existing_state_error() {
  local existing_state

  echo "Existing managed Kali VM state detected."
  echo "'omarchy-kali-vm install' only supports first-time setup."
  echo "Remove the existing VM before reinstalling: omarchy-kali-vm remove"
  echo ""
  echo "Detected managed state:"
  while IFS= read -r existing_state; do
    printf '  %s\n' "$existing_state"
  done < <(list_existing_managed_state_paths)
}

path_state_label() {
  local managed_path="$1"

  if [[ -e "$managed_path" ]]; then
    printf 'present'
  else
    printf 'not present'
  fi
}

print_remove_preview() {
  echo "Managed Kali VM targets scheduled for deletion:"
  printf '  Config directory: %s (%s)\n' "$KALI_CONFIG_DIR" "$(path_state_label "$KALI_CONFIG_DIR")"
  printf '  Compose file:     %s (%s)\n' "$COMPOSE_FILE" "$(path_state_label "$COMPOSE_FILE")"
  printf '  Storage directory:%s (%s)\n' " $KALI_STORAGE" "$(path_state_label "$KALI_STORAGE")"
  printf '  Shared directory: %s (%s)\n' "$KALI_SHARED_DIR" "$(path_state_label "$KALI_SHARED_DIR")"
  printf '  Runtime launcher: %s (%s)\n' "$RUNTIME_DESKTOP_FILE" "$(path_state_label "$RUNTIME_DESKTOP_FILE")"
}

show_usage() {
  echo "Usage: omarchy-kali-vm [command] [options]"
  echo ""
  echo "Commands:"
  echo "  install [--debug]    Install and configure Kali VM (first-time setup only)"
  echo "  remove [--debug]     Remove Kali VM and all its data"
  echo "  launch [options]     Start Kali VM (if needed) and connect via SPICE"
  echo "                       Options:"
  echo "                         --keep-alive, -k   Keep VM running after viewer closes"
  echo "  stop                 Stop the running Kali VM"
  echo "  status               Show current VM status"
  echo "  verify-image         Verify qemux/qemu image digest matches expected"
  echo "  help                 Show this help message"
  echo ""
  echo "Examples:"
  echo "  omarchy-kali-vm install           # Set up Kali VM for first time"
  echo "  omarchy-kali-vm install --debug   # Keep install evidence and write a debug report"
  echo "  omarchy-kali-vm launch            # Connect to VM (auto-stop on exit)"
  echo "  omarchy-kali-vm launch -k         # Connect to VM (keep running)"
  echo "  omarchy-kali-vm remove --debug    # Remove runtime state but preserve archives and image"
  echo "  omarchy-kali-vm stop              # Shut down the VM"
  echo ""
  echo "Notes:"
  echo "  install will exit if managed Kali VM state already exists."
  echo "  Closing the viewer powers down the VM by default."
  echo ""
  echo "Optional Omarchy integration:"
  echo "  omarchy-kali-vm-integrate-os"
  echo "  omarchy-kali-vm-unintegrate-os"
}
