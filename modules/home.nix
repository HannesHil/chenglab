{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  programs.git = lib.mkMerge [
    (lib.mkIf (pkgs.stdenv.isDarwin) {
      enable = true;
      userName = "Eric Cheng";
      userEmail = "eric@chengeric.com";
      delta = {
        enable = true;
      };
      signing = {
        key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIkcgwjYMHqUDnx0JIOSXQ/TN80KEaFvvUWA2qH1AHFC";
        signByDefault = true;
        gpgPath = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      };
      extraConfig = {
        gpg = {format = "ssh";};
      };
    })
    (lib.mkIf (pkgs.stdenv.isLinux) {
      enable = true;
      delta = {
        enable = true;
      };
    })
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    syntaxHighlighting = {
      enable = true;
    };
    shellAliases = {
      cat = "bat --style=plain --theme=base16 --paging=never ";
      e = "eza ";
      v = "vim ";
      sudo = "sudo ";
      z = "zellij ";
      ".." = "cd ..";
    };
    # https://discourse.nixos.org/t/zsh-zplug-powerlevel10k-zshrc-is-readonly/30333
    initExtra = ''
      fortune

      if [[ -z "$ZELLIJ" ]]; then
        zellij attach default || zellij --session default
        exit
      fi

      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
    '';
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
  };

  programs.helix = {
    enable = true;
    defaultEditor = true;
    settings = {
      theme = "dark_high_contrast";
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zellij = {
    enable = true;
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  home = {
    username = "eh8";
    homeDirectory = lib.mkMerge [
      (lib.mkIf pkgs.stdenv.isLinux "/home/eh8")
      (lib.mkIf pkgs.stdenv.isDarwin "/Users/eh8")
    ];
    stateVersion = "23.11";
    packages = with pkgs; [
      bat
      btop
      croc
      duf
      eza
      fortune-kind
      just
      kopia
      neofetch
      sops
      tealdeer
    ];
    file = {
      ".p10k.zsh".source = ./../utils/p10k.zsh;
    };
  };
}
