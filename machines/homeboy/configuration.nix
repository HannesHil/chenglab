{
  inputs,
  outputs,
  ...
}: {
  imports = [
    inputs.impermanence.nixosModules.impermanence

    ./hardware-configuration.nix

    ./../../modules/nixos/base.nix
    ./../../modules/nixos/remote-unlock.nix
    #./../../modules/nixos/auto-update.nix

    #./../../services/tailscale.nix
    # ./../../services/netdata.nix
    #./../../services/nextcloud.nix
  ];

  networking.hostName = "homeboy";
  services.btrfs.autoScrub.enable = true;
  services.btrfs.autoScrub.interval = "weekly";
}
