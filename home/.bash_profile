# antrel-os: login shell. Logging in on the first text console starts Hyprland (as a systemd session via uwsm).
[[ -f ~/.bashrc ]] && . ~/.bashrc

if uwsm check may-start; then
    exec uwsm start hyprland.desktop
fi
