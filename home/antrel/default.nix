{ ... }:
{
  home.username = "antrel";
  home.homeDirectory = "/home/antrel";
  home.stateVersion = "26.11";

  # Plain Lua file in the repo, linked into place; layout and binds live there.
  xdg.configFile."hypr/hyprland.lua".source = ./hyprland.lua;

  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };
    settings = {
      # Translucent background; Hyprland blurs what is behind it.
      background_opacity = "0.85";
      window_padding_width = 12;
      confirm_os_window_close = 0;
      enable_audio_bell = false;
    };
  };

  programs.bash.enable = true;
  # Prompt hides user@host unless connected over SSH.
  programs.starship.enable = true;

  programs.git = {
    enable = true;
    settings.user = {
      name = "AntrelL";
      email = "Nikitagaliant03@bk.ru";
    };
  };

  # `gh auth login` once; git then pushes to GitHub through gh's credentials.
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  # GTK4 (Nautilus etc.) skips hinting by default since 4.16 and looks soft at ~96 DPI.
  # GTK reads these through the settings portal.
  dconf.settings."org/gnome/desktop/interface" = {
    font-rendering = "manual";
    font-antialiasing = "rgba";
    font-rgba-order = "rgb";
    font-hinting = "slight";
  };
}
