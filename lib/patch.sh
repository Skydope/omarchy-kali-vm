# lib/patch.sh — QCOW2 offline patching, host-side.
# Rewritten from original container-based approach to run directly on the host
# with explicit sudo commands. Eliminates the --privileged Docker container
# from the trust path for privileged operations.
#
# Requires lib/config.sh, lib/debug.sh sourced first.
# Host dependencies: qemu-nbd, qemu-img, sfdisk, e2fsck, resize2fs, parted, openssl.

check_prerequisites() {
  local DISK_SIZE_GB=${1:-64}
  local REQUIRED_SPACE=$((DISK_SIZE_GB + 10))

  if [[ ! -e /dev/kvm ]]; then
    gum style \
      --border normal \
      --padding "1 2" \
      --margin "1" \
      "KVM virtualization not available!" \
      "" \
      "Please enable virtualization in BIOS or run:" \
      "  sudo modprobe kvm-intel  # for Intel CPUs" \
      "  sudo modprobe kvm-amd    # for AMD CPUs"
    exit 1
  fi

  AVAILABLE_SPACE=$(df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}')
  if (( AVAILABLE_SPACE < REQUIRED_SPACE )); then
    echo "Insufficient disk space!"
    echo "   Available: ${AVAILABLE_SPACE}GB"
    echo "   Required: ${REQUIRED_SPACE}GB (${DISK_SIZE_GB}GB disk + 10GB overhead)"
    exit 1
  fi
}

patch_qcow2() {
  local NEW_USERNAME="$1"
  local NEW_PASSWORD="$2"
  local DISK_SIZE="$3"

  if [[ ! -f "$KALI_STORAGE/data.qcow2" ]]; then
    echo "ERROR: QCOW2 image not found"
    return 1
  fi

  echo "Configuring Kali image..."

  local QCOW2="$KALI_STORAGE/data.qcow2"
  local NBD_DEV=""
  local PART_NBD_DEV=""
  local MNT="/tmp/kali-mount-$$"
  local NBD_CONNECTED=false
  local PART_NBD_CONNECTED=false
  local MNT_ACTIVE=false
  local START_SECTOR=""
  local PATCH_FAILED=false

  cleanup() {
    if [[ "$MNT_ACTIVE" == "true" ]]; then
      sudo umount "$MNT" 2>/dev/null || true
    fi
    if [[ "$PART_NBD_CONNECTED" == "true" && -n "$PART_NBD_DEV" ]]; then
      sudo qemu-nbd --disconnect "$PART_NBD_DEV" 2>/dev/null || true
      wait_for_nbd_disconnect "$PART_NBD_DEV" || true
    fi
    if [[ "$NBD_CONNECTED" == "true" && -n "$NBD_DEV" ]]; then
      sudo qemu-nbd --disconnect "$NBD_DEV" 2>/dev/null || true
      wait_for_nbd_disconnect "$NBD_DEV" || true
    fi
    sudo rmdir "$MNT" 2>/dev/null || true

    if [[ "$PATCH_FAILED" == "true" ]]; then
      echo "Patching failed. Invalidating QCOW2 so retry starts from clean extraction."
      rm -f "$QCOW2" "$KALI_STORAGE/.configured"
    fi
  }

  wait_for_nbd_disconnect() {
    local dev_name timeout
    dev_name=$(basename "$1")
    timeout=30

    while (( timeout > 0 )); do
      if [[ ! -e "/sys/block/$dev_name/pid" ]]; then
        return 0
      fi
      sleep 1
      (( timeout-- ))
    done

    echo "ERROR: Timed out waiting for $1 to disconnect."
    return 1
  }

  trap cleanup EXIT

  # Expand virtual disk if requested size exceeds current
  local QEMU_INFO CURRENT_GB REQUESTED_GB
  QEMU_INFO=$(qemu-img info "$QCOW2")
  CURRENT_GB=$(awk '/virtual size/{print int($3)}' <<< "$QEMU_INFO")
  REQUESTED_GB=${DISK_SIZE%%[gG]}
  if (( REQUESTED_GB > CURRENT_GB )); then
    echo "Resizing virtual disk from ${CURRENT_GB}G to ${REQUESTED_GB}G..."
    qemu-img resize "$QCOW2" "$DISK_SIZE"
  fi

  # Find a free NBD device — host-side, must not collide with other VMs
  for dev in /dev/nbd{0..7}; do
    if [[ -b "$dev" ]] && ! grep -q "$(basename "$dev")" /proc/partitions 2>/dev/null; then
      NBD_DEV="$dev"
      break
    fi
  done

  if [[ -z "$NBD_DEV" ]]; then
    echo "ERROR: No free NBD device found."
    exit 1
  fi

  # ANTI-DISASTER GUARD: affirm target is an NBD device, never a real block device
  if [[ ! "$NBD_DEV" =~ ^/dev/nbd[0-9]+$ ]]; then
    echo "FATAL: target no es un dispositivo NBD: $NBD_DEV" >&2
    PATCH_FAILED=true
    exit 1
  fi

  sudo qemu-nbd --connect="$NBD_DEV" "$QCOW2"
  NBD_CONNECTED=true
  sleep 2

  # Find and expand root partition
  local ROOT_PART_PATH ROOT_PART_NUM PARTITION_LISTING LARGEST_PART_PATH
  ROOT_PART_PATH=$(lsblk -nrpo NAME,TYPE,FSTYPE "$NBD_DEV" | awk '$2 == "part" && ($3 == "ext4" || $3 == "ext3" || $3 == "ext2" || $3 == "xfs" || $3 == "btrfs") {print $1; exit}')
  LARGEST_PART_PATH=$(lsblk -nrbo NAME,SIZE,TYPE "$NBD_DEV" | awk '$3 == "part" {print $1, $2}' | sort -k2 -nr | awk 'NR == 1 {print $1}')
  PARTITION_LISTING=$(sudo sfdisk -l "$NBD_DEV" 2>/dev/null || true)

  if [[ -n "$ROOT_PART_PATH" ]]; then
    ROOT_PART_NUM=$(grep -oP '\d+$' <<< "$ROOT_PART_PATH" || true)
  fi

  if [[ -z "$ROOT_PART_NUM" && -n "$LARGEST_PART_PATH" ]]; then
    ROOT_PART_NUM=$(grep -oP '\d+$' <<< "$LARGEST_PART_PATH" || true)
  fi

  if [[ -z "$ROOT_PART_NUM" ]]; then
    local ROOT_PART_LINE
    ROOT_PART_LINE=$(awk '$2 == "*" && ($6 == "83" || $6 == "Linux") {print; exit}' <<< "$PARTITION_LISTING")
    if [[ -z "$ROOT_PART_LINE" ]]; then
      ROOT_PART_LINE=$(awk '$5 == "83" || $6 == "83" || /Linux/ {print; exit}' <<< "$PARTITION_LISTING")
    fi
    ROOT_PART_NUM=$(grep -oP '\d+$' <<< "$ROOT_PART_LINE" || true)
  fi

  if [[ -n "$ROOT_PART_NUM" ]]; then
    echo "Expanding partition ${NBD_DEV}p${ROOT_PART_NUM}..."

    local ROOT_PART_DEF PARTITION_DUMP BOOT_FLAG
    PARTITION_DUMP=$(sudo sfdisk -d "$NBD_DEV" 2>/dev/null)
    ROOT_PART_DEF=$(grep "${NBD_DEV}p${ROOT_PART_NUM}" <<< "$PARTITION_DUMP")
    START_SECTOR=$(awk -F'[=, ]+' '{for(i=1;i<=NF;i++) if($i=="start") print $(i+1)}' <<< "$ROOT_PART_DEF")

    BOOT_FLAG=""
    if grep -q "bootable" <<< "$ROOT_PART_DEF"; then
      BOOT_FLAG=",*"
    fi

    echo "${START_SECTOR},+,L${BOOT_FLAG}" | sudo sfdisk -N "$ROOT_PART_NUM" "$NBD_DEV" --force --no-reread
    sudo blockdev --rereadpt "$NBD_DEV" 2>/dev/null || true
    sudo partx -u "$NBD_DEV" 2>/dev/null || true
    sleep 1

    sudo qemu-nbd --disconnect "$NBD_DEV"
    NBD_CONNECTED=false
    wait_for_nbd_disconnect "$NBD_DEV" || true

    # Attach root partition directly via offset
    for dev in /dev/nbd{0..7}; do
      if [[ -b "$dev" ]] && ! grep -q "$(basename "$dev")" /proc/partitions 2>/dev/null; then
        PART_NBD_DEV="$dev"
        break
      fi
    done

    if [[ -z "$PART_NBD_DEV" ]]; then
      echo "ERROR: No free secondary nbd device found for partition mapping."
      lsblk || true
      PATCH_FAILED=true
      exit 1
    fi

    if [[ ! "$PART_NBD_DEV" =~ ^/dev/nbd[0-9]+$ ]]; then
      echo "FATAL: target no es un dispositivo NBD: $PART_NBD_DEV" >&2
      PATCH_FAILED=true
      exit 1
    fi

    local PART_OFFSET=$((START_SECTOR * 512))
    sudo qemu-nbd --offset="$PART_OFFSET" --connect="$PART_NBD_DEV" "$QCOW2"
    PART_NBD_CONNECTED=true
    sleep 2

    if [[ ! -b "$PART_NBD_DEV" ]]; then
      echo "ERROR: Failed to map root partition device: $PART_NBD_DEV"
      lsblk || true
      PATCH_FAILED=true
      exit 1
    fi

    sudo e2fsck -f -y "$PART_NBD_DEV"
    sudo resize2fs "$PART_NBD_DEV"
  fi

  # Mount root partition
  sudo mkdir -p "$MNT"
  local ROOT_FOUND=false
  local PARTITION_CANDIDATES
  PARTITION_CANDIDATES=$(lsblk -nrpo NAME,TYPE "$NBD_DEV" | awk '$2 == "part" {print $1}')
  for part in "$PART_NBD_DEV" $PARTITION_CANDIDATES "$NBD_DEV"; do
    if [[ -b "$part" ]]; then
      if sudo mount "$part" "$MNT" 2>/dev/null; then
        if [[ -d "$MNT/etc/systemd" ]]; then
          ROOT_FOUND=true
          MNT_ACTIVE=true
          break
        fi
        sudo umount "$MNT"
      fi
    fi
  done
  if [[ "$ROOT_FOUND" != "true" ]]; then
    echo "ERROR: Could not find root partition"
    PATCH_FAILED=true
    exit 1
  fi

  # Credentials — password via stdin to avoid plaintext in /proc
  local PASS_HASH
  PASS_HASH=$(openssl passwd -6 -stdin <<< "$NEW_PASSWORD")
  sudo sed -i "s|^kali:[^:]*:|kali:${PASS_HASH}:|" "$MNT/etc/shadow"

  if [[ "$NEW_USERNAME" != "kali" ]]; then
    sudo sed -i "s/^kali:/${NEW_USERNAME}:/" "$MNT/etc/passwd"
    sudo sed -i "s|/home/kali|/home/${NEW_USERNAME}|" "$MNT/etc/passwd"
    sudo sed -i "s/^kali:/${NEW_USERNAME}:/" "$MNT/etc/shadow"
    sudo sed -i "s/^kali:/${NEW_USERNAME}:/" "$MNT/etc/group"
    sudo sed -i "s/^kali:/${NEW_USERNAME}:/" "$MNT/etc/gshadow"
    sudo sed -i "s/,kali/,${NEW_USERNAME}/g" "$MNT/etc/group"
    sudo sed -i "s/,kali/,${NEW_USERNAME}/g" "$MNT/etc/gshadow"
    sudo mv "$MNT/home/kali" "$MNT/home/${NEW_USERNAME}"
  fi

  local HOME_DIR="$MNT/home/$NEW_USERNAME"
  local GUEST_SHARED_MOUNT="$HOME_DIR/Kali"

  sudo mkdir -p "$MNT/etc/sudoers.d"
  sudo tee "$MNT/etc/sudoers.d/90-omarchy-kali-user" > /dev/null << EOF
$NEW_USERNAME ALL=(ALL:ALL) ALL
EOF
  sudo chmod 440 "$MNT/etc/sudoers.d/90-omarchy-kali-user"

  sudo mkdir -p "$GUEST_SHARED_MOUNT"
  sudo sed -i '\|[[:space:]]/home/[^[:space:]]\+/Kali[[:space:]]\+9p[[:space:]]|d' "$MNT/etc/fstab"
  printf 'shared /home/%s/Kali 9p trans=virtio,version=9p2000.L,rw,nofail,x-systemd.automount,_netdev 0 0\n' "$NEW_USERNAME" | sudo tee -a "$MNT/etc/fstab" > /dev/null

  echo "xfce4-session" | sudo tee "$HOME_DIR/.xsession" > /dev/null

  local XFCE_DIR="$HOME_DIR/.config/xfce4/xfconf/xfce-perchannel-xml"
  sudo mkdir -p "$XFCE_DIR"

  sudo tee "$XFCE_DIR/xfce4-screensaver.xml" > /dev/null << 'XFCEXML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="saver" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
  <property name="lock" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
</channel>
XFCEXML

  sudo tee "$XFCE_DIR/xfce4-power-manager.xml" > /dev/null << 'XFCEXML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="dpms-enabled" type="bool" value="false"/>
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="dpms-on-ac-sleep" type="uint" value="0"/>
    <property name="dpms-on-ac-off" type="uint" value="0"/>
    <property name="power-button-action" type="uint" value="4"/>
  </property>
</channel>
XFCEXML

  sudo tee "$XFCE_DIR/xfce4-session.xml" > /dev/null << 'XFCEXML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="SaveOnExit" type="bool" value="false"/>
  </property>
  <property name="shutdown" type="empty">
    <property name="ShowHibernate" type="bool" value="false"/>
    <property name="ShowSuspend" type="bool" value="false"/>
  </property>
</channel>
XFCEXML

  sudo tee "$MNT/usr/local/bin/spice-autoresize" > /dev/null << 'RESIZESH'
#!/bin/bash
restart_spice_vdagent() {
  if ! command -v spice-vdagent >/dev/null 2>&1; then
    return
  fi

  pkill -x spice-vdagent 2>/dev/null || true
  spice-vdagent >/dev/null 2>&1 &
}

reload_xfce_desktop() {
  if ! command -v xfdesktop >/dev/null 2>&1; then
    return
  fi

  xfdesktop --reload >/dev/null 2>&1 || true
}

while true; do
  OUTPUT=$(xrandr 2>/dev/null | awk '/ connected/ {print $1; exit}')
  PREFERRED=$(xrandr 2>/dev/null | awk '/connected/ {found=1; next} found && /+/ {print $1; exit}')
  CURRENT=$(xrandr 2>/dev/null | awk '/connected/ {found=1; next} found && /\*/ {print $1; exit}')
  if [[ -n "$PREFERRED" && "$PREFERRED" != "$CURRENT" ]]; then
    if [[ -n "$OUTPUT" ]]; then
      xrandr --output "$OUTPUT" --auto 2>/dev/null
    fi
    reload_xfce_desktop
    restart_spice_vdagent
  fi
  sleep 1
done
RESIZESH
  sudo chmod +x "$MNT/usr/local/bin/spice-autoresize"

  local AUTOSTART_DIR="$HOME_DIR/.config/autostart"
  sudo mkdir -p "$AUTOSTART_DIR"
  sudo tee "$AUTOSTART_DIR/spice-autoresize.desktop" > /dev/null << 'DESKTOPFILE'
[Desktop Entry]
Type=Application
Name=SPICE Auto Resize
Exec=/usr/local/bin/spice-autoresize
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESKTOPFILE

  local uid gid
  uid=$(grep "^${NEW_USERNAME}:" "$MNT/etc/passwd" | cut -d: -f3)
  gid=$(grep "^${NEW_USERNAME}:" "$MNT/etc/passwd" | cut -d: -f4)
  sudo chown "${uid}:${gid}" "$HOME_DIR/.xsession"
  sudo chown "${uid}:${gid}" "$GUEST_SHARED_MOUNT"
  sudo chown -R "${uid}:${gid}" "$HOME_DIR/.config"

  # Cleanup before exit
  MNT_ACTIVE=false
  sudo umount "$MNT"
  if [[ "$PART_NBD_CONNECTED" == "true" ]]; then
    PART_NBD_CONNECTED=false
    sudo qemu-nbd --disconnect "$PART_NBD_DEV"
    wait_for_nbd_disconnect "$PART_NBD_DEV" || true
  fi
  if [[ "$NBD_CONNECTED" == "true" ]]; then
    NBD_CONNECTED=false
    sudo qemu-nbd --disconnect "$NBD_DEV"
    wait_for_nbd_disconnect "$NBD_DEV" || true
  fi
  sudo rmdir "$MNT" 2>/dev/null || true

  # Suppress the EXIT trap since cleanup already completed successfully
  trap - EXIT

  echo "Kali image configured."
}
