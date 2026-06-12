# lib/docker.sh — Docker helpers, dependency checking, and compose generation.
# Extracted from original bin/omarchy-kali-vm. Requires lib/config.sh sourced first.

docker_available() {
  command -v docker >/dev/null 2>&1
}

docker_compose_available() {
  docker_available && docker compose version >/dev/null 2>&1
}

require_command() {
  local command_name="$1"
  local package_hint="${2:-$1}"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name"
    echo "Install the package that provides it before continuing: $package_hint"
    exit 1
  fi
}

require_compose() {
  if ! docker compose version >/dev/null 2>&1; then
    echo "docker compose is required."
    echo "Install Docker with the compose plugin and ensure the daemon is running."
    exit 1
  fi
}

best_effort_remove_docker_artifacts() {
  if docker_compose_available; then
    docker compose -f "$COMPOSE_FILE" down 2>/dev/null || echo "Warning: Docker Compose shutdown failed during removal; continuing."
  elif docker_available; then
    echo "Skipping Docker Compose shutdown during removal: docker compose is unavailable or Docker is not ready."
  else
    echo "Skipping Docker cleanup during removal: docker is unavailable."
  fi

  if [[ "$DEBUG_MODE" = true ]]; then
    if docker_available; then
      DEBUG_IMAGE_ACTION="preserved"
    else
      DEBUG_IMAGE_ACTION="preserved-docker-unavailable"
    fi
    return 0
  fi

  if docker_available; then
    if docker rmi qemux/qemu 2>/dev/null; then
      DEBUG_IMAGE_ACTION="removed-if-present"
    else
      echo "Skipping Docker image removal during removal: image is unavailable or Docker is not ready."
      DEBUG_IMAGE_ACTION="remove-attempted"
    fi
  else
    DEBUG_IMAGE_ACTION="skipped-docker-unavailable"
  fi
}

check_common_dependencies() {
  require_command docker docker
  require_command gum gum
  require_command sudo sudo
  require_compose
}

check_remove_dependencies() {
  require_command gum gum
}

check_install_dependencies() {
  check_common_dependencies
  require_command curl curl
  require_command gpg gnupg
  require_command remote-viewer virt-viewer
  require_command sha256sum coreutils
  require_command qemu-nbd qemu-img
  require_command qemu-img qemu-img
  require_command sfdisk util-linux
  require_command resize2fs e2fsprogs
  require_command parted parted
  require_command openssl openssl
  require_command 7z 7zip
}

check_launch_dependencies() {
  check_common_dependencies
  require_command remote-viewer virt-viewer
}

kali_qemu_arguments() {
  echo "-spice unix=on,addr=/storage/spice.sock,disable-ticketing=on -device qemu-xhci -device usb-tablet -device virtio-serial-pci -chardev spicevmc,id=vdagent,name=vdagent -device virtserialport,chardev=vdagent,name=com.redhat.spice.0"
}

write_kali_start_hook() {
  mkdir -p "$KALI_CONFIG_DIR"

  cat << 'EOF' | tee "$KALI_CONFIG_DIR/start.sh" > /dev/null
#!/bin/bash
set -e

if qemu-system-x86_64 -spice help >/dev/null 2>&1; then
  exit 0
fi

echo "Installing QEMU SPICE module..."
# Run apt as root (no _apt sandbox) because cap_drop ALL blocks chown/chmod
# that apt's privilege-drop needs. Use a temp cache directory owned by root.
mkdir -p /tmp/apt-cache
DEBIAN_FRONTEND=noninteractive apt-get -qq update
DEBIAN_FRONTEND=noninteractive apt-get -qq --no-install-recommends -y \
  -o APT::Sandbox::User=root \
  -o Dir::Cache::archives=/tmp/apt-cache \
  install qemu-system-modules-spice > /dev/null
rm -rf /tmp/apt-cache /var/lib/apt/lists/*
EOF

  chmod +x "$KALI_CONFIG_DIR/start.sh"
}

ensure_kali_runtime_config() {
  write_kali_start_hook

  if [[ -f "$COMPOSE_FILE" ]]; then
    local QEMU_ARGUMENTS
    QEMU_ARGUMENTS=$(kali_qemu_arguments)
    sed -i "s|^\([[:space:]]*ARGUMENTS:\).*|\1 \"$QEMU_ARGUMENTS\"|" "$COMPOSE_FILE"
  fi
}

parse_debug_flag() {
  local subcommand="$1"
  shift

  DEBUG_MODE=false
  if [[ $# -eq 0 ]]; then
    return 0
  fi

  case "$1" in
    --debug)
      if [[ $# -ne 1 ]]; then
        echo "Unknown option(s) for $subcommand: ${*:2}" >&2
        exit 1
      fi
      prepare_debug_run "$subcommand"
      ;;
    *)
      echo "Unknown option for $subcommand: $1" >&2
      exit 1
      ;;
  esac
}

cleanup_stale_data_disk() {
  if [[ -f "$KALI_STORAGE/data.qcow2" ]] && [[ -f "$KALI_STORAGE/data.img" ]]; then
    echo "Removing stale qemux data disk from earlier failed boot attempt..."
    rm -f "$KALI_STORAGE/data.img"
  fi
}
