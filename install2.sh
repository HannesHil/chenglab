#!/bin/sh

set -e -u -o pipefail

# Become root
sudo -i

# Load German keyboard layout
loadkeys de

# --- Step: Select Target Disk ---
echo "--------------------------------------------------------------------"
echo "Available block devices (disks):"
lsblk -dno NAME,SIZE,MODEL
echo "--------------------------------------------------------------------"
echo "WARNING: ALL DATA ON THE SELECTED DISK WILL BE DELETED!"
read -p "Enter the name of the target disk (e.g., sda, sdb, nvme0n1): " TARGET_DISK_NAME

if [ -z "$TARGET_DISK_NAME" ]; then
    echo "No disk selected. Exiting."
    exit 1
fi

TARGET_DISK="/dev/${TARGET_DISK_NAME}"

echo "You have selected ${TARGET_DISK} for installation."
read -p "ARE YOU ABSOLUTELY SURE? This will wipe all data on ${TARGET_DISK}. Type 'yes' to confirm: " CONFIRMATION
if [ "$CONFIRMATION" != "yes" ]; then
    echo "Installation aborted by user."
    exit 1
fi
echo "--------------------------------------------------------------------"

# Ensure an internet connection is available if needed for the installation
echo "INFO: Please ensure an internet connection is available!"
echo "--------------------------------------------------------------------"

clear

# Display disk layout
echo -e "\n\033[1mDisk Layout:\033[0m"
lsblk
echo ""

# Partitioning the selected disk with GPT
echo "--------------------------------------------------------------------"
echo "WARNING: ALL DATA ON ${TARGET_DISK} WILL BE DELETED!"
echo "You have 5 seconds to abort with Strg+C."
echo "--------------------------------------------------------------------"
sleep 5

echo "Partitioning ${TARGET_DISK}..."

parted -s "${TARGET_DISK}" mklabel gpt
echo "Creating EFI partition (1GB)..."
parted -s "${TARGET_DISK}" mkpart NIXBOOT fat32 1MiB 1025MiB
parted -s "${TARGET_DISK}" set 1 esp on

echo "Creating NixOS root partition for LUKS (rest of disk)..."
parted -s "${TARGET_DISK}" mkpart NIX btrfs 1025MiB 100%

echo "Partitioning complete."
echo "Partitions on ${TARGET_DISK}:"
parted -s "${TARGET_DISK}" print
echo "--------------------------------------------------------------------"

# Allow kernel to recognize new partitions
echo "Waiting for kernel to recognize new partitions..."
sync
sleep 3
partprobe "${TARGET_DISK}"
sleep 2

# Define partition variables based on TARGET_DISK
PARTITION_PREFIX=""
if echo "$TARGET_DISK" | grep -q "nvme"; then
    PARTITION_PREFIX="p"
fi

EFI_PARTITION="${TARGET_DISK}${PARTITION_PREFIX}1"
ROOT_PARTITION="${TARGET_DISK}${PARTITION_PREFIX}2"

# Check if partitions exist before formatting
echo "Checking for partition devices: $EFI_PARTITION and $ROOT_PARTITION"
if [ ! -b "$EFI_PARTITION" ] || [ ! -b "$ROOT_PARTITION" ]; then
    echo "ERROR: Partitions $EFI_PARTITION or $ROOT_PARTITION not found. Exiting."
    lsblk "${TARGET_DISK}"
    exit 1
fi
echo "INFO: Partitions $EFI_PARTITION and $ROOT_PARTITION found."

echo "Formatting partitions..."

echo "Formatting $EFI_PARTITION as FAT32 (BOOT)..."
mkfs.fat -F 32 -n NIXBOOT "$EFI_PARTITION"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to format $EFI_PARTITION. Exiting."
    exit 1
fi
echo "$EFI_PARTITION formatted as FAT32."
echo "--------------------------------------------------------------------"

# --- Step: Create and open LUKS container ---
echo "--------------------------------------------------------------------"
echo "CREATING LUKS ENCRYPTION."
echo "You will now be prompted to set a strong passphrase for $ROOT_PARTITION."
echo "--------------------------------------------------------------------"
sleep 2
cryptsetup luksFormat --type luks2 "$ROOT_PARTITION"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create LUKS container. Exiting."
    exit 1
fi

LUKS_MAPPED_NAME="nix-root"
cryptsetup open "$ROOT_PARTITION" "$LUKS_MAPPED_NAME"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to open LUKS container. Exiting."
    exit 1
fi

LUKS_DEVICE="/dev/mapper/$LUKS_MAPPED_NAME"

echo "LUKS container created and opened. Mapped device is $LUKS_DEVICE."
echo "--------------------------------------------------------------------"

# Now format the Btrfs filesystem inside the LUKS container
echo "Formatting $LUKS_DEVICE as Btrfs (NIX)..."
mkfs.btrfs -f -L NIX "$LUKS_DEVICE"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to format $LUKS_DEVICE. Exiting."
    exit 1
fi
echo "$LUKS_DEVICE formatted as Btrfs."
echo "--------------------------------------------------------------------"

echo "Formatting complete."
echo "--------------------------------------------------------------------"

# --- Step: Create Btrfs subvolumes ---
echo "Creating Btrfs subvolumes..."

TEMP_BTRFS_MOUNT="/mnt/btrfs_tmp"
mkdir -p "$TEMP_BTRFS_MOUNT"
if ! mount -t btrfs "$LUKS_DEVICE" "$TEMP_BTRFS_MOUNT"; then
    echo "ERROR: Failed to mount Btrfs from $LUKS_DEVICE. Exiting."
    exit 1
fi

btrfs subvolume create "$TEMP_BTRFS_MOUNT/@"
btrfs subvolume create "$TEMP_BTRFS_MOUNT/@home"
btrfs subvolume create "$TEMP_BTRFS_MOUNT/@nix"
btrfs subvolume create "$TEMP_BTRFS_MOUNT/@log"

echo "Btrfs subvolumes created:"
btrfs subvolume list "$TEMP_BTRFS_MOUNT"

umount "$TEMP_BTRFS_MOUNT"
rmdir "$TEMP_BTRFS_MOUNT"
echo "--------------------------------------------------------------------"

# --- Step: Mount filesystems and subvolumes ---
echo "Mounting filesystems..."

NIXOS_MOUNT_POINT="/mnt"
BTRFS_OPTS="subvol=@,compress=zstd,noatime,space_cache=v2,discard=async"
BTRFS_HOME_OPTS="subvol=@home,compress=zstd,noatime,space_cache=v2,discard=async"
BTRFS_NIX_OPTS="subvol=@nix,compress=zstd,noatime,space_cache=v2,discard=async"
BTRFS_LOG_OPTS="subvol=@log,compress=zstd,noatime,space_cache=v2,discard=async,nodatacow"

echo "Mounting root subvolume to $NIXOS_MOUNT_POINT..."
mkdir -p "$NIXOS_MOUNT_POINT"
if ! mount -o "$BTRFS_OPTS" "$LUKS_DEVICE" "$NIXOS_MOUNT_POINT"; then
    echo "ERROR: Failed to mount Btrfs root subvolume from $LUKS_DEVICE. Exiting."
    exit 1
fi

echo "Mounting other Btrfs subvolumes..."
mkdir -p "${NIXOS_MOUNT_POINT}/home"
if ! mount -o "$BTRFS_HOME_OPTS" "$LUKS_DEVICE" "${NIXOS_MOUNT_POINT}/home"; then
    echo "ERROR: Failed to mount @home subvolume. Exiting."
    umount "$NIXOS_MOUNT_POINT"
    exit 1
fi

mkdir -p "${NIXOS_MOUNT_POINT}/nix"
if ! mount -o "$BTRFS_NIX_OPTS" "$LUKS_DEVICE" "${NIXOS_MOUNT_POINT}/nix"; then
    echo "ERROR: Failed to mount @nix subvolume. Exiting."
    umount "${NIXOS_MOUNT_POINT}/home"
    umount "$NIXOS_MOUNT_POINT"
    exit 1
fi

mkdir -p "${NIXOS_MOUNT_POINT}/var"
mkdir -p "${NIXOS_MOUNT_POINT}/var/log"
if ! mount -o "$BTRFS_LOG_OPTS" "$LUKS_DEVICE" "${NIXOS_MOUNT_POINT}/var/log"; then
    echo "ERROR: Failed to mount @log subvolume. Exiting."
    umount "${NIXOS_MOUNT_POINT}/nix"
    umount "${NIXOS_MOUNT_POINT}/home"
    umount "$NIXOS_MOUNT_POINT"
    exit 1
fi

echo "Mounting EFI partition $EFI_PARTITION..."
mkdir -p "${NIXOS_MOUNT_POINT}/boot"
if ! mount "$EFI_PARTITION" "${NIXOS_MOUNT_POINT}/boot"; then
    echo "ERROR: Failed to mount EFI partition $EFI_PARTITION. Exiting."
    umount -R "$NIXOS_MOUNT_POINT"
    exit 1
fi

echo "All filesystems mounted successfully."
echo "Current mounts under $NIXOS_MOUNT_POINT:"
lsblk "${NIXOS_MOUNT_POINT}"
echo "--------------------------------------------------------------------"

# --- Step: Generate NixOS configuration ---
echo "Generating NixOS configuration files..."

nixos-generate-config --root "$NIXOS_MOUNT_POINT"
if [ $? -ne 0 ]; then
    echo "ERROR: nixos-generate-config failed. Exiting."
    umount -R "$NIXOS_MOUNT_POINT"
    exit 1
fi
echo "hardware-configuration.nix generated in ${NIXOS_MOUNT_POINT}/etc/nixos/"

# Create a basic configuration.nix with LUKS options
echo "Creating a basic configuration.nix..."
CONFIG_FILE="${NIXOS_MOUNT_POINT}/etc/nixos/configuration.nix"
HARDWARE_CONFIG_FILE_NAME="hardware-configuration.nix"

mkdir -p "$(dirname "$CONFIG_FILE")"

# This part is crucial for LUKS.
# Note the added 'boot.initrd.luks.devices' section.
# The 'device' path should point to the raw partition.
# The 'name' is the mapped name we chose earlier.

cat > "$CONFIG_FILE" << EOF
{ config, pkgs, ... }:

{
  imports = [ ./${HARDWARE_CONFIG_FILE_NAME} ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable LUKS encryption
  boot.initrd.luks.devices = {
    root = {
      device = "${ROOT_PARTITION}";
      name = "${LUKS_MAPPED_NAME}";
      preLVM = true; # Not needed for Btrfs but good practice for other setups
    };
  };

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "de_DE.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "de";
  };
  networking.useDHCP = true;
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";
  users.users.hannes = {
    isNormalUser = true;
    description = "This is my user";
    extraGroups = [ "networkmanager" "wheel" ];
    initialHashedPassword = "";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPqXUtpGuEjknNH4Rqbe65DqNceyq5N7+427r8bEJfgG hannes@nixos"
    ];
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    neovim
    wget
    curl
    git
    htop
    btrfs-progs
  ];

  system.stateVersion = "25.05";
}
EOF

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create ${CONFIG_FILE}. Exiting."
    umount -R "$NIXOS_MOUNT_POINT"
    exit 1
fi

echo "${CONFIG_FILE} created successfully."
echo "--------------------------------------------------------------------"
echo "IMPORTANT: Review and edit ${NIXOS_MOUNT_POINT}/etc/nixos/configuration.nix"
echo "and hardware-configuration.nix. The script will proceed with "
echo "nixos-install in 15 seconds. Press Ctrl+C to abort and edit manually."
echo "--------------------------------------------------------------------"
sleep 15

# --- Step: Install NixOS ---
echo "Starting NixOS installation (nixos-install)..."
echo "This will take some time. Please be patient."

NIXOS_INSTALL_LOG="${NIXOS_MOUNT_POINT}/nixos-install.log"
echo "Installation log will be saved to ${NIXOS_INSTALL_LOG}"

if ! nixos-install --root "$NIXOS_MOUNT_POINT" --no-root-passwd > "${NIXOS_INSTALL_LOG}" 2>&1; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "ERROR: nixos-install failed."
    echo "Check the log for details: ${NIXOS_INSTALL_LOG}"
    echo "You might still be in the installation environment. You can try to"
    echo "fix issues in ${NIXOS_MOUNT_POINT}/etc/nixos/configuration.nix and"
    echo "rerun 'nixos-install --root ${NIXOS_MOUNT_POINT}'"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
fi

echo "--------------------------------------------------------------------"
echo "NixOS installation completed successfully!"
echo "--------------------------------------------------------------------"
echo ""
echo "Next steps:"
echo "1. Unmount all partitions: umount -R ${NIXOS_MOUNT_POINT}"
echo "2. Close the LUKS container: cryptsetup close ${LUKS_MAPPED_NAME}"
echo "3. Reboot your system: reboot"
echo ""
echo "After rebooting, you will be prompted for your LUKS passphrase."
echo "Then, log in with the user you configured and set a password if you haven't."
echo "Example: sudo passwd yourusername"
echo "--------------------------------------------------------------------"
