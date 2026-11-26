-- antrel-os Hyprland config (Lua format, Hyprland >= 0.55).
-- Look follows docs/design/reference-01-floating-pills.png.
-- Wiki: https://wiki.hypr.land/configuring/

------------------
---- MONITORS ----
------------------

-- Native resolution, scale 1 on every output: fractional scaling blurs text.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})

------------------
---- PROGRAMS ----
------------------

-- `uwsm app` puts each app in its own systemd scope inside the session.
local terminal    = "uwsm app -- kitty"
local fileManager = "uwsm app -- nautilus"
local browser     = "uwsm app -- firefox"
local dms         = "dms ipc call "

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 6,
        gaps_out = 14,

        border_size = 1,
        col = {
            active_border   = "rgba(ffffff40)",
            inactive_border = "rgba(ffffff14)",
        },

        resize_on_border = true,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding       = 14,
        rounding_power = 2,

        -- Translucency comes per app (kitty); browsers and editors stay opaque.
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 20,
            render_power = 3,
            color        = 0x66000000,
        },

        blur = {
            enabled  = true,
            size     = 10,
            passes   = 3,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Curves and animations: Hyprland's defaults.
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}    } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}  } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, damping = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })

hl.config({
    dwindle = {
        preserve_split = true,
    },
    misc = {
        -- The shell draws the wallpaper.
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
    layers = {
        allow_new_top_layers_over_existing_fullscreen = true,
    },
})

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us,ru",
        kb_options = "grp:alt_shift_toggle", -- Alt+Shift, as on Windows
        follow_mouse = 1,
        sensitivity  = 0,
    },
})

---------------------
---- KEYBINDINGS ----
---------------------
-- Windows habits where they exist: Win+E, Win+L, Win+V, Win+I, Win+A, Win+N,
-- Win+Tab, Win+X, Alt+Tab, Alt+F4, Win+Shift+S, Ctrl+Shift+Esc.

local mainMod = "SUPER"

-- Start menu: tap Win alone, or Win+Space.
hl.bind(mainMod .. " + SUPER_L", hl.dsp.exec_cmd(dms .. "launcher toggle"), { release = true })
hl.bind(mainMod .. " + Space",   hl.dsp.exec_cmd(dms .. "launcher toggle"))

-- Apps
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd(browser))

-- Shell panels
hl.bind(mainMod .. " + L",          hl.dsp.exec_cmd(dms .. "lock lock"))
hl.bind(mainMod .. " + V",          hl.dsp.exec_cmd(dms .. "clipboard toggle"))
hl.bind(mainMod .. " + I",          hl.dsp.exec_cmd(dms .. "settings toggle"))
hl.bind(mainMod .. " + A",          hl.dsp.exec_cmd(dms .. "control-center toggle"))
hl.bind(mainMod .. " + N",          hl.dsp.exec_cmd(dms .. "notifications toggle"))
hl.bind(mainMod .. " + X",          hl.dsp.exec_cmd(dms .. "powermenu toggle"))
hl.bind(mainMod .. " + Tab",        hl.dsp.exec_cmd(dms .. "hypr toggleOverview"))
hl.bind("CTRL + SHIFT + Escape",    hl.dsp.exec_cmd(dms .. "processlist toggle"))

-- Windows
hl.bind("ALT + F4",                 hl.dsp.window.close())
hl.bind(mainMod .. " + Q",          hl.dsp.window.close())
hl.bind(mainMod .. " + F",          hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F",  hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + J",          hl.dsp.layout("togglesplit"))
hl.bind("ALT + Tab",                hl.dsp.window.cycle_next({}))
hl.bind("ALT + SHIFT + Tab",        hl.dsp.window.cycle_next({ next = false }))

-- Focus with Win+arrows, move windows with Win+Shift+arrows (also across monitors).
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mainMod .. " + " .. dir,         hl.dsp.focus({ direction = dir }))
    hl.bind(mainMod .. " + SHIFT + " .. dir, hl.dsp.window.move({ direction = dir }))
end

-- Workspaces: Win+[0-9] switch, Win+Shift+[0-9] send the window there.
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Win + left/right mouse drag: move/resize.
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots to clipboard: region (Win+Shift+S) or whole screen (Print).
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
hl.bind("Print",                   hl.dsp.exec_cmd("grim - | wl-copy"))

-- Media keys go through the shell so its on-screen indicators show.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(dms .. "audio increment 5"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(dms .. "audio decrement 5"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(dms .. "audio mute"),        { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd(dms .. "mic mute"),          { locked = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd(dms .. "mpris playPause"),   { locked = true })
hl.bind("XF86AudioPause",       hl.dsp.exec_cmd(dms .. "mpris playPause"),   { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd(dms .. "mpris next"),        { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd(dms .. "mpris previous"),    { locked = true })

-----------------------
---- WINDOW RULES -----
-----------------------

hl.window_rule({
    -- Apps don't get to maximize themselves; tiling decides the size.
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland.
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})
