{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    supportedFilesystems = [ "btrfs" ];
    initrd = {
      # `readlink /sys/class/net/enp0s31f6/device/driver` indicates "r8169" is the ethernet driver for this device
      availableKernelModules = ["nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" "r8169"];
      luks = {
        reusePassphrases = true;
        devices = {
          "cryptroot" = {
            device = "/dev/nvme0n1p2";
            allowDiscards = true;
          };
        };
      };
    };
  };

  fileSystems = {
    "/" = {
      device = "none";
      fsType = "tmpfs";
      options = ["defaults" "size=8G" "mode=0755"];
    };
    "/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
      options = ["umask=0077"];
    };
    "/nix" = {
      device = "/dev/mapper/cryptroot";
      fsType = "btrfs";
      options = ["compress=zstd" "noatime" "subvol=@nix"];
    };
    "/home" = {
      device = "/dev/mapper/cryptroot";
      fsType = "btrfs";
      options = ["compress=zstd" "subvol=@home"];
    };
    "/images" = {
      device = "/dev/mapper/cryptroot";
      fsType = "btrfs";
      options = ["compress=zstd" "subvol=@images"];
    };
  };

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
