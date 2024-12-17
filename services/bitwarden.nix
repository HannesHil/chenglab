{config, ...}: {

  services.vaultwarden = {
    enable = true;
  };

  services.vaultwarden.config = {
  ROCKET_ADDRESS = "0.0.0.0";
  ROCKET_PORT = 8111;
  }

  networking.firewall.allowedTCPPorts = [
    8111
  ];
}
