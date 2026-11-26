# Live ISO for installing antrel-os: the official GNOME installer with a text GRUB menu.
# The stock ISO's graphical GRUB menu hangs, blanks the screen or drops back to the firmware
# on Chinese X99 boards in UEFI mode (nixpkgs#427235); text mode boots.
# Build: `nix build .#iso` (see README).
{ modulesPath, ... }:
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-graphical-gnome.nix" ];

  nixpkgs.hostPlatform = "x86_64-linux";
  isoImage.forceTextMode = true;
}
