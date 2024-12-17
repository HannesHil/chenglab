{config, ...}: {

  services.vaultwarden = {
    enable = true;
  };

  networking.firewall.allowedTCPPorts = [
    8222
  ];
}
