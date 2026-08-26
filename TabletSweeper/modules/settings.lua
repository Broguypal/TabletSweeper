require('tables')
local config = require('config')

local defaults = T{
    collapsed = false,

    radius       = 50.0,   
    cell         = 1.0,
    conservative = true,  

    update_hz         = 6,
    autosave_seconds  = 60,

    pos       = {x = 20, y = 20},
    view      = 300,
    zoom_span = 320,
    zoom_min  = 60,
    zoom_step = 50,
    zoom_max  = 2600,
    zoom_px   = 256,      -- zoom pane texture: 128 / 256 / 512 / 1024 (cost rises ~4x per step)
    fog_alpha = 0.6,
    colors = {
        unseen = {r = 118, g = 118, b = 124},
        seen   = {r = 58, g = 96,  b = 68},
        player = {r = 255, g = 48, b = 48},
        sweep  = {r = 255, g = 214, b = 64},
        panel  = {r = 12, g = 12, b = 18},
        border = {r = 70, g = 78, b = 96},
        button = {r = 38, g = 42, b = 54},
        button_hot = {r = 62, g = 72, b = 92},
        danger = {r = 130, g = 38, b = 40},
    },
}

local settings = config.load(defaults)

return settings
