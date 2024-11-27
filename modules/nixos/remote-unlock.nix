{config, ...}: {
  boot.kernelParams = ["ip=dhcp"];
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      shell = "/bin/cryptsetup-askpass";
      authorizedKeys = config.users.users.eh8.openssh.authorizedKeys.keys;
      hostKeys = ["/nix/secret/ssh_host"];
    };
  };
}
