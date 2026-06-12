# lib/lifecycle.sh — VM launch, stop, graceful shutdown, and status.
# Extracted from original bin/omarchy-kali-vm with SPICE socket permission fix applied.
# Requires lib/config.sh, lib/docker.sh, lib/ui.sh sourced first.

launch_kali() {
  check_launch_dependencies
  KEEP_ALIVE=false
  if [[ "${1:-}" = "--keep-alive" ]] || [[ "${1:-}" = "-k" ]]; then
    KEEP_ALIVE=true
  fi

  if [[ ! -f $COMPOSE_FILE ]]; then
    echo "Kali VM not configured. Please run: omarchy-kali-vm install"
    exit 1
  fi

  ensure_kali_runtime_config

  CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)

  local SPICE_SOCK="$KALI_STORAGE/spice.sock"

  if [[ $CONTAINER_STATUS != "running" ]]; then
    echo "Starting Kali VM..."
    notify_if_available "Starting Kali VM" "This can take 15-30 seconds" -t 15000

    rm -f "$SPICE_SOCK"
    cleanup_stale_data_disk

    if ! docker compose -f "$COMPOSE_FILE" up -d 2>&1; then
      echo "Failed to start Kali VM!"
      notify_if_available -u critical "Kali VM" "Failed to start Kali VM"
      exit 1
    fi
  fi

  echo "Waiting for Kali VM to be ready..."
  WAIT_COUNT=0
  until [[ -S "$SPICE_SOCK" ]]; do
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if (( WAIT_COUNT > 60 )); then
      echo "Timeout: Kali VM SPICE not ready within 2 minutes"
      notify_if_available -u critical "Kali VM" "SPICE not ready"
      exit 1
    fi
  done
  docker exec "$CONTAINER_NAME" chown "$(id -u):$(id -g)" /storage/spice.sock
  docker exec "$CONTAINER_NAME" chmod 660 /storage/spice.sock

  if [[ -t 1 ]]; then
    if [[ $KEEP_ALIVE = "true" ]]; then
      LIFECYCLE="VM will keep running after viewer closes
To stop: omarchy-kali-vm stop"
    else
      LIFECYCLE="VM will auto-stop when viewer closes"
    fi
    gum style \
      --border normal \
      --padding "1 2" \
      --margin "1" \
      --align center \
      "Connecting to Kali VM" \
      "" \
      "$LIFECYCLE"
  fi

  remote-viewer "spice+unix://$SPICE_SOCK" -t "Kali VM" --auto-resize=always

  if [[ $KEEP_ALIVE = "false" ]]; then
    echo ""
    echo "SPICE session closed. Stopping Kali VM..."
    graceful_shutdown
    echo "Kali VM stopped."
  else
    echo ""
    echo "SPICE session closed. Kali VM is still running."
    echo "To stop it: omarchy-kali-vm stop"
  fi
}

graceful_shutdown() {
  if docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null | grep -q running; then
    echo "Sending ACPI shutdown to guest..."
    docker exec "$CONTAINER_NAME" bash -c 'echo "system_powerdown" | nc -q1 localhost 7100' 2>/dev/null || true
    while docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null | grep -q running; do
      local WAIT=0
      sleep 2
      WAIT=$((WAIT + 1))
      if (( WAIT > 30 )); then
        echo "Guest did not shut down within 60s, forcing stop..."
        break
      fi
    done
  fi
  docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
  rm -f "$KALI_STORAGE/spice.sock"
}

stop_kali() {
  check_common_dependencies
  if [[ ! -f $COMPOSE_FILE ]]; then
    echo "Kali VM not configured."
    exit 1
  fi

  echo "Stopping Kali VM..."
  graceful_shutdown
  echo "Kali VM stopped."
}

status_kali() {
  check_common_dependencies
  if [[ ! -f $COMPOSE_FILE ]]; then
    echo "Kali VM not configured."
    echo "To set up: omarchy-kali-vm install"
    exit 1
  fi

  CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)

  if [[ -z $CONTAINER_STATUS ]]; then
    echo "Kali VM container not found."
    echo "To start: omarchy-kali-vm launch"
  elif [[ $CONTAINER_STATUS = "running" ]]; then
    gum style \
      --border normal \
      --padding "1 2" \
      --margin "1" \
      --align left \
      "Kali VM Status: RUNNING" \
      "" \
      "To connect: omarchy-kali-vm launch" \
      "To stop:    omarchy-kali-vm stop"
  else
    echo "Kali VM is stopped (status: $CONTAINER_STATUS)"
    echo "To start: omarchy-kali-vm launch"
  fi
}
