{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  # https://nixcademy.com/2024/01/15/nix-on-macos/
  environment.systemPackages = with pkgs; [
    # nix development stuff
    nixos-rebuild
    nil
    alejandra
    # useful cli tools
  ];

  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;
  nix.settings.experimental-features = "nix-command flakes";

  programs.zsh.enable = true;

  system.defaults = {
    dock.autohide = true;
    dock.mru-spaces = false;
    finder.AppleShowAllExtensions = true;
    finder.FXPreferredViewStyle = "clmv";
    loginwindow.LoginwindowText = "If lost, contact eric@chengeric.com";
    screencapture.location = "~/OneDrive/30-39 Hobbies/34 Photos/";
    screensaver.askForPasswordDelay = 10;
  };

  # Mute that loud ass bootup sound
  system.activationScripts.extraActivation.text = ''
    nvram StartupMute=%01
  '';

  security.pam.enableSudoTouchIdAuth = true;

  users.users.eh8.home = "/Users/eh8";

  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = "eh8";
  };

  homebrew = {
    enable = true;
    global = {
      autoUpdate = false;
    };
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
    };
    casks = [
      "1password"
      "1password-cli"
      "alacritty"
      "audacity"
      "betterdisplay"
      "caffeine"
      "camo-studio"
      "cursor"
      "discord"
      "dropbox"
      "firefox"
      "font-ibm-plex"
      "font-inter"
      "font-iosevka-ss08"
      "font-marcellus"
      "font-noto-sans"
      "font-roboto-slab"
      "google-chrome"
      "handbrake"
      "inkscape"
      "mac-mouse-fix"
      "mpv"
      "ngrok"
      "obsidian"
      "rar"
      "raycast"
      "screen-studio"
      "sidequest"
      "spotify"
      "the-unarchiver"
      "transmission"
      "visual-studio-code"
      "zed"
      "vlc"
    ];
    masApps = {
      "1Password for Safari" = 1569813296;
      "GarageBand" = 682658836;
      "Infuse" = 1136220934;
      "Messenger" = 1480068668;
      "Microsoft Excel" = 462058435;
      "Microsoft PowerPoint" = 462062816;
      "Microsoft Word" = 462054704;
      "OneDrive" = 823766827;
      "Tailscale" = 1475387142;
    };
  };

  system.stateVersion = 4;
}