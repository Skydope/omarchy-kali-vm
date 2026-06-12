# lib/config.sh — XDG paths, constants, and global configuration.
# Source this file first. The guard prevents double-sourcing under set -e.
if [[ -n "${__OMARCHY_KALI_VM_CONFIG_LOADED:-}" ]]; then
    return 0
fi

CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-kali-vm"
COMPOSE_FILE="$CONFIG_ROOT/kali/docker-compose.yml"
KALI_CONFIG_DIR="$CONFIG_ROOT/kali"
KALI_STORAGE="$HOME/.kali"
KALI_SHARED_DIR="$HOME/Kali"
CONTAINER_NAME="${OMARCHY_KALI_VM_CONTAINER_NAME:-omarchy-kali-vm}"
USER_APPLICATIONS_DIR="$DATA_ROOT/applications"
RUNTIME_DESKTOP_FILE="$USER_APPLICATIONS_DIR/omarchy-kali-vm.desktop"

# qemux/qemu image digest — pinned for integrity, not trust establishment.
# Bump process: verify Dockerfile + entrypoint upstream, docker pull, docker inspect.
# Verificado: 2026-06-12 por Skydope (Docker Hub manifest list)
readonly QEMU_IMAGE_DIGEST="qemux/qemu@sha256:d987eaf928e4cbef1e17ab5f5db5f0e830cc9e7f69da78e26fbf3c6524be0b4f"

# Kali archive signing key fingerprints — allowlist for VALIDSIG verification.
# These are primary key fingerprints. When Kali rotates keys, add the new
# fingerprint here. Same bump process as QEMU_IMAGE_DIGEST: verify against
# official Kali docs before updating.
# Verificado contra docs oficiales de Kali: 2026-06-12 por Skydope
readonly KALI_ALLOWED_FINGERPRINTS=(
  "827C8569F2518CC677FECA1AED65462EC8D5E4C5"  # Archive Signing Key (2025) — firma actual
  "44C6513A8E4FB3D30875F758ED444FF07D8D0BF6"  # Kali Linux Repository (legacy, aún en keyring)
)

readonly __OMARCHY_KALI_VM_CONFIG_LOADED=1
