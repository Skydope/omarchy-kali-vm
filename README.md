# omarchy-kali-vm

Provides an accessible "click-to-install" Kali Linux VM using a dockerized QEMU environment. Intended for [Omarchy](https://github.com/basecamp/omarchy), but works on any Arch setup with Docker. Supports clipboard sharing, display auto-resizing, and borderless integration on Hyprland.

> This is a security-hardened fork of [r3b1s/omarchy-kali-vm](https://github.com/r3b1s/omarchy-kali-vm).
> Key changes: QCOW2 patching runs host-side (no `--privileged` container), GPG fingerprint
> allowlist with `VALID SIG` verification, pinned Docker image digest, hardened runtime container.

## Installation

### From source

```sh
git clone https://github.com/Skydope/omarchy-kali-vm.git
cd omarchy-kali-vm
sudo make install
```

### AUR (coming soon)

```sh
yay -S omarchy-kali-vm
```

### Dependencies

| Dependency | Package | Notes |
|-----------|---------|-------|
| `docker` + compose plugin | docker | Container runtime |
| `gum` | gum | Interactive TUI prompts |
| `curl` | curl | Downloading archives and keys |
| `gpg` | gnupg | Cryptographic verification |
| `remote-viewer` | virt-viewer | SPICE display client |
| `sha256sum` | coreutils | Checksum verification |
| `sudo` | sudo | NBD module loading, privileged patching |
| `qemu-nbd`, `qemu-img` | qemu-base | QCOW2 offline patching (host-side) |
| `sfdisk`, `lsblk`, `blockdev` | util-linux | Partition manipulation |
| `e2fsck`, `resize2fs` | e2fsprogs | Filesystem resize |
| `parted` | parted | Partition probing |
| `openssl` | openssl | Password hashing |
| `7z` | 7zip | Archive extraction (verify with `pacman -F 7z`) |

After installation run `omarchy-kali-vm-integrate-os` to import Hyprland windowrules and Walker menu entries.

## Commands

- `omarchy-kali-vm install [--debug]`
- `omarchy-kali-vm launch [-k|--keep-alive]`
- `omarchy-kali-vm stop`
- `omarchy-kali-vm status`
- `omarchy-kali-vm verify-image`
- `omarchy-kali-vm remove [--debug]`
- `omarchy-kali-vm-integrate-os`
- `omarchy-kali-vm-unintegrate-os`

## Security

- **GPG verification**: Kali archive signing keys verified against an allowlist of known fingerprints using `--status-fd` + `VALIDSIG` (immune to key-bundle attacks).
- **Image pinning**: `qemux/qemu` Docker image pinned by SHA256 digest. Run `omarchy-kali-vm verify-image` to check.
- **No privileged containers**: QCOW2 patching runs host-side with explicit `sudo` commands. Docker Hub is removed from the privileged trust path.
- **Runtime hardening**: Container runs with `no-new-privileges`, `cap_drop: ALL`, only `NET_ADMIN` granted.
- **SPICE socket**: `chown` + `chmod 660` — only the owning user can connect.

## Cleanup

- Remove VM data: `omarchy-kali-vm remove`
- Remove VM data preserving debug artifacts: `omarchy-kali-vm remove --debug`
- Remove Omarchy integration: `omarchy-kali-vm-unintegrate-os`
- Remove the package: `sudo make uninstall`

## License

MIT — forked from [r3b1s/omarchy-kali-vm](https://github.com/r3b1s/omarchy-kali-vm).
