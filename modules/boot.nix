# GRUB on the shared Windows ESP; kernels stay in /boot on btrfs.
# The ESP is ~200 MB with ~144 MB free: too small for NixOS kernel generations.
{
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot/efi";
    };
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      configurationLimit = 20;
      # Text menu: graphical GRUB (gfxterm) hangs on this X99 board in UEFI mode (nixpkgs#427235).
      # A font alone switches GRUB to gfxterm, so both must be null.
      font = null;
      splashImage = null;
    };
  };
}
