{config, ...}: {
  boot.kernelParams = ["ip=dhcp"];
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      shell = "/bin/cryptsetup-askpass";
      authorizedKeys = config.users.users.hannes.openssh.authorizedKeys.keys;
      hostKeys = ["/nix/secret/initrd/ssh_initrd_key"];
    };
  };
}
