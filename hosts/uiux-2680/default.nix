{ inputs, ... }:
{
  imports = [
    ./hardware.nix
    ../../modules/core.nix
    ../../modules/boot.nix
    ../../modules/nvidia.nix
    ../../modules/audio.nix
    ../../modules/performance.nix
    ../../modules/desktop.nix
    ../../modules/fonts.nix
    ../../modules/happ.nix
    inputs.home-manager.nixosModules.home-manager
    inputs.omp.nixosModules.default
  ];

  networking.hostName = "uiux-2680";

  # Windows keeps the RTC in local time; match it so the clock is right in both OSes.
  time.hardwareClockInLocalTime = true;

  # Explicit Windows entry instead of os-prober: deterministic, no NTFS probing.
  boot.loader.grub.extraEntries = ''
    menuentry "Windows 11" {
      insmod part_gpt
      insmod fat
      search --no-floppy --fs-uuid --set=root 0041-D5AC
      chainloader /EFI/Microsoft/Boot/bootmgfw.efi
    }
  '';

  programs.omp.enable = true;
  services.happ.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.antrel = import ../../home/antrel;
  };

  system.stateVersion = "26.11";
}
