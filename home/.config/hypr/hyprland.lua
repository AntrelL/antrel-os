-- antrel-os: base Hyprland config, until the desktop shell is chosen.
-- Docs: https://wiki.hypr.land/Configuring/Start/ (0.57 reads only hyprland.lua; API: hl.config, hl.bind, hl.dsp.*)
-- Check after editing: hyprctl configerrors

local mod      = "SUPER"
local terminal = "kitty"
local browser  = "firefox"
local launcher = "fuzzel"

---- MONITORS ----
-- Every output at its preferred mode, placed automatically. Per-output rules: names from `hyprctl monitors`.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

---- AUTOSTART ----
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")
end)

---- INPUT ----
hl.config({
    input = {
        kb_layout = "us,ru",
        kb_options = "grp:alt_shift_toggle", -- Alt+Shift switches the layout, as in Windows
        follow_mouse = 1,
        -- Same feel as Windows, where the pointer slider is 6/20 (x0.5) and "Enhance pointer precision" is off.
        -- Flat = no acceleration; libinput's flat factor is 1 + sensitivity.
        accel_profile = "flat",
        sensitivity = -0.5,
    },
})

---- LOOK ----
hl.config({
    general = {
        gaps_in = 4,
        gaps_out = 8,
        border_size = 1,
        resize_on_border = true,
        layout = "dwindle",
    },
    decoration = {
        rounding = 8,
    },
    dwindle = { preserve_split = true },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})

---- KEYS ----
hl.bind(mod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + D", hl.dsp.exec_cmd(launcher))
hl.bind(mod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())

hl.bind(mod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down", hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + SHIFT + left", hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mod .. " + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. " + SHIFT + down", hl.dsp.window.move({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots to the clipboard: whole screen / selected area.
hl.bind("Print", hl.dsp.exec_cmd("grim - | wl-copy"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd([[sh -c 'grim -g "$(slurp)" - | wl-copy']]))

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
