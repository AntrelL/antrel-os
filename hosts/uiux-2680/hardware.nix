# HUANANZHI X99-QD4, Xeon E5-2680 v4, single NVMe shared with Windows 11.
# Compare with `nixos-generate-config --show-hardware-config` during install.
{
  config,
  lib,
  modulesPath,
  ...
}:
let
  # One btrfs partition labelled "nixos"; subvolumes are created at install time.
  btrfs = subvol: {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [
      "subvol=${subvol}"
      "compress=zstd"
      "noatime"
    ];
  };
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  fileSystems."/" = btrfs "@";
  fileSystems."/home" = btrfs "@home";
  fileSystems."/nix" = btrfs "@nix";

  # Existing Windows ESP (FAT32, 196 MB). Serial read from Windows: 4314540 = 0041-D5AC.
  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/0041-D5AC";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
