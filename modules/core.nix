{ pkgs, ... }:
{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nixpkgs.config.allowUnfree = true;

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Minsk";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # 16 GB RAM: compressed swap in RAM instead of a swap partition.
  zramSwap.enable = true;

  users.users.antrel = {
    isNormalUser = true;
    # Fixed: performance.nix tunes user-1000.slice.
    uid = 1000;
    description = "Antrel";
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
    ];
  };

  # Lets prebuilt Linux binaries (downloaded tools, game launchers) find their loader and libs.
  programs.nix-ld.enable = true;

  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
    htop
  ];
}
