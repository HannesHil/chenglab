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
# read -p "Press Enter to continue, or Ctrl+C to abort."

# Clear screen before showing disk layout
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

# Create a new GPT partition table
parted -s "${TARGET_DISK}" mklabel gpt
echo "Creating EFI partition (1GB)..."
parted -s "${TARGET_DISK}" mkpart NIXBOOT fat32 1MiB 1025MiB
parted -s "${TARGET_DISK}" set 1 esp on

# Create the root partition for NixOS with Btrfs (remaining space)
# Starts after the 1GB ESP (1025MiB)
echo "Creating NixOS root partition (rest of disk)..."
parted -s "${TARGET_DISK}" mkpart NIX btrfs 1025MiB 100%

echo "Partitioning complete."
echo "Partitions on ${TARGET_DISK}:"
parted -s "${TARGET_DISK}" print
echo "--------------------------------------------------------------------"

# Allow kernel to recognize new partitions
echo "Waiting for kernel to recognize new partitions..."
sync
sleep 3 # Give a moment for the kernel to catch up
partprobe "${TARGET_DISK}"
sleep 2


# Define partition variables based on TARGET_DISK
# Handle naming difference for NVMe drives (e.g., /dev/nvme0n1p1 vs /dev/sda1)
PARTITION_PREFIX=""
if echo "$TARGET_DISK" | grep -q "nvme"; then
    PARTITION_PREFIX="p"
fi

EFI_PARTITION="${TARGET_DISK}${PARTITION_PREFIX}1"
ROOT_PARTITION="${TARGET_DISK}${PARTITION_PREFIX}2"

# Check if partitions exist before formatting
echo "Checking for partition devices: $EFI_PARTITION and $ROOT_PARTITION"
if [ ! -b "$EFI_PARTITION" ] || [ ! -b "$ROOT_PARTITION" ]; then
    echo "ERROR: Partitions $EFI_PARTITION or $ROOT_PARTITION not found after partprobe. Please check manually. Exiting."
    lsblk "${TARGET_DISK}" # Show layout for debugging
    exit 1
fi
echo "INFO: Partitions $EFI_PARTITION and $ROOT_PARTITION found."


echo "Formatting partitions..."

# Format the EFI System Partition as FAT32
echo "Formatting $EFI_PARTITION as FAT32 (BOOT)..."
mkfs.fat -F 32 -n NIXBOOT "$EFI_PARTITION"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to format $EFI_PARTITION. Exiting."
    exit 1
fi
echo "$EFI_PARTITION formatted as FAT32."
echo "--------------------------------------------------------------------"

# Format the Root Partition as Btrfs
echo "Formatting $ROOT_PARTITION as Btrfs (NIX)..."
mkfs.btrfs -f -L NIX -m single "$ROOT_PARTITION"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to format $ROOT_PARTITION. Exiting."
    exit 1
fi
echo "$ROOT_PARTITION formatted as Btrfs."
echo "--------------------------------------------------------------------"

echo "Formatting complete."
echo "--------------------------------------------------------------------"

# --- Step: Create Btrfs subvolumes ---
echo "Creating Btrfs subvolumes..."

# Mount the top-level Btrfs filesystem to create subvolumes
TEMP_BTRFS_MOUNT="/mnt/btrfs_tmp"
mkdir -p "$TEMP_BTRFS_MOUNT"
if ! mount -t btrfs "$ROOT_PARTITION" "$TEMP_BTRFS_MOUNT"; then
    echo "ERROR: Failed to mount top-level Btrfs at $TEMP_BTRFS_MOUNT using $ROOT_PARTITION. Exiting."
    exit 1
fi

# Create subvolumes
btrfs subvolume create "$TEMP_BTRFS_MOUNT/@"
btrfs subvolume create "$TEMP_BTRFS_MOUNT/@home"
btrfs subvolume create "$TEMP_BTRFS_MOUNT/@nix"
btrfs subvolume create "$TEMP_BTRFS_MOUNT/@log"

echo "Btrfs subvolumes created:"
btrfs subvolume list "$TEMP_BTRFS_MOUNT"

# Unmount the top-level Btrfs filesystem
umount "$TEMP_BTRFS_MOUNT"
rmdir "$TEMP_BTRFS_MOUNT"
echo "--------------------------------------------------------------------"

# --- Step: Mount filesystems and subvolumes ---
echo "Mounting filesystems..."

# Define the main NixOS mount point
NIXOS_MOUNT_POINT="/mnt"

BTRFS_OPTS="subvol=@,compress=zstd,noatime,space_cache=v2,discard=async"
BTRFS_HOME_OPTS="subvol=@home,compress=zstd,noatime,space_cache=v2,discard=async"
BTRFS_NIX_OPTS="subvol=@nix,compress=zstd,noatime,space_cache=v2,discard=async"
BTRFS_LOG_OPTS="subvol=@log,compress=zstd,noatime,space_cache=v2,discard=async,nodatacow"

# Mount root subvolume
echo "Mounting root subvolume to $NIXOS_MOUNT_POINT..."
mkdir -p "$NIXOS_MOUNT_POINT"
if ! mount -o "$BTRFS_OPTS" "$ROOT_PARTITION" "$NIXOS_MOUNT_POINT"; then
    echo "ERROR: Failed to mount Btrfs root subvolume from $ROOT_PARTITION. Exiting."
    exit 1
fi

# Create and mount other subvolume mount points
echo "Mounting other Btrfs subvolumes..."
mkdir -p "${NIXOS_MOUNT_POINT}/home"
if ! mount -o "$BTRFS_HOME_OPTS" "$ROOT_PARTITION" "${NIXOS_MOUNT_POINT}/home"; then
    echo "ERROR: Failed to mount @home subvolume. Exiting."
    umount "$NIXOS_MOUNT_POINT"
    exit 1
fi

mkdir -p "${NIXOS_MOUNT_POINT}/nix"
if ! mount -o "$BTRFS_NIX_OPTS" "$ROOT_PARTITION" "${NIXOS_MOUNT_POINT}/nix"; then
    echo "ERROR: Failed to mount @nix subvolume. Exiting."
    umount "${NIXOS_MOUNT_POINT}/home"
    umount "$NIXOS_MOUNT_POINT"
    exit 1
fi

mkdir -p "${NIXOS_MOUNT_POINT}/var" # Ensure /var exists
mkdir -p "${NIXOS_MOUNT_POINT}/var/log"
if ! mount -o "$BTRFS_LOG_OPTS" "$ROOT_PARTITION" "${NIXOS_MOUNT_POINT}/var/log"; then
    echo "ERROR: Failed to mount @log subvolume. Exiting."
    umount "${NIXOS_MOUNT_POINT}/nix"
    umount "${NIXOS_MOUNT_POINT}/home"
    umount "$NIXOS_MOUNT_POINT"
    exit 1
fi

# Mount EFI/boot partition
echo "Mounting EFI partition $EFI_PARTITION..."
mkdir -p "${NIXOS_MOUNT_POINT}/boot"
if ! mount "$EFI_PARTITION" "${NIXOS_MOUNT_POINT}/boot"; then
    echo "ERROR: Failed to mount EFI partition $EFI_PARTITION. Exiting."
    umount -R "$NIXOS_MOUNT_POINT" # Attempt to clean up
    exit 1
fi

echo "All filesystems mounted successfully."
echo "Current mounts under $NIXOS_MOUNT_POINT:"
lsblk "${NIXOS_MOUNT_POINT}" # Consider 'lsblk $TARGET_DISK' to show the whole disk context
echo "--------------------------------------------------------------------"

# --- Step: Generate NixOS configuration ---
echo "Generating NixOS configuration files..."

# Generate hardware-configuration.nix
echo "Generating hardware-configuration.nix..."
# Ensure nixos-generate-config references the correct disk for fileSystems."/" device if it uses it
# It should pick up the mounted devices correctly from /mnt
nixos-generate-config --root "$NIXOS_MOUNT_POINT"
if [ $? -ne 0 ]; then
    echo "ERROR: nixos-generate-config failed. Exiting."
    umount -R "$NIXOS_MOUNT_POINT"
    exit 1
fi
echo "hardware-configuration.nix generated in ${NIXOS_MOUNT_POINT}/etc/nixos/"
# It's a good idea to replace the guessed device for / in hardware-configuration.nix with PARTLABEL
# This is an advanced step not automatically done here.
echo "INFO: You might want to edit hardware-configuration.nix later to use PARTLABEL for mounts."
echo "--------------------------------------------------------------------"

# Create a basic configuration.nix
echo "Creating a basic configuration.nix..."
CONFIG_FILE="${NIXOS_MOUNT_POINT}/etc/nixos/configuration.nix"
HARDWARE_CONFIG_FILE_NAME="hardware-configuration.nix" # Used in the heredoc

mkdir -p "$(dirname "$CONFIG_FILE")"

cat > "$CONFIG_FILE" << EOF
# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page,
# available online at https://nixos.org/manual/nixos/stable/options
# and in the NixOS options search tool: https://search.nixos.org/options

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of a typical hardware scan.
      ./${HARDWARE_CONFIG_FILE_NAME}
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # For systemd-boot, ensure the ESP is mounted at /boot
  # The hardware-configuration.nix should correctly identify it.
  # Example from hardware-configuration.nix for /boot:
  # fileSystems."/boot" =
  #   { device = "/dev/disk/by-label/NIXBOOT";
  #     fsType = "vfat";
  #   };


  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "de_DE.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "de";
  };

  # Configure networking.
  networking.useDHCP = true;
  # Or configure specific interface:
  # networking.interfaces.eth0.useDHCP = true; # Replace eth0 with your interface name
  # networking.hostName = "nixos"; # Define your hostname.

  # Enable the SSH daemon.
  services.openssh.enable = true;
  services.openssh.permitRootLogin = "no";

  # Define a user account.
  users.users.hannes = {
    isNormalUser = true;
    description = "This is my user";
    extraGroups = [ "networkmanager" "wheel" ];
    initialHashedPassword = "$y$j9T$YwEJtdPGfadgAhoaW96qA.$qOCMKJJrAT3co7SM3LCsAI6u4EyLg5CQ4aFq7OZrHZ1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPqXUtpGuEjknNH4Rqbe65DqNceyq5N7+427r8bEJfgG hannes@nixos"
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    neovim
    wget
    curl
    git
    htop
    btrfs-progs
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion).
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
echo "IMPORTANT: Review and edit ${NIXOS_MOUNT_POINT}/etc/nixos/configuration.nix and"
echo "           ${NIXOS_MOUNT_POINT}/etc/nixos/${HARDWARE_CONFIG_FILE_NAME} NOW!"
echo "           Especially set your username, password (or plan to set it), timezone, and system.stateVersion."
echo "           The script will proceed with nixos-install in 15 seconds."
echo "           Press Ctrl+C to abort and edit manually."
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
echo "2. Reboot your system: reboot"
echo ""
echo "After rebooting, log in with the user you configured and set a password if you haven't."
echo "Example: sudo passwd yourusername"
echo "--------------------------------------------------------------------"
