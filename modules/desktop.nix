# Hyprland + Dux Shell (formerly DankMaterialShell) + its greeter.
{ pkgs, ... }:
{
  programs.hyprland = {
    enable = true;
    # UWSM runs Hyprland as a systemd session: graphical-session.target starts dms.service.
    withUWSM = true;
  };

  programs.dux-shell.enable = true;

  services.displayManager.dux-greeter = {
    enable = true;
    compositor.name = "hyprland";
    # Greeter mirrors the wallpaper and theme chosen in the shell.
    configHome = "/home/antrel";
  };

  # File pickers and settings for GTK apps; Hyprland's portal handles screen sharing.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  programs.dconf.enable = true;

  # Electron/Chromium apps run as native Wayland clients.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Trash, network locations and phones in Nautilus.
  services.gvfs.enable = true;

  environment.systemPackages = with pkgs; [
    nautilus
    # Screenshots: Win+Shift+S / Print in hyprland.lua.
    grim
    slurp
    wl-clipboard
  ];
}
