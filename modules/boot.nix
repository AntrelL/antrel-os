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
    };
  };
}
