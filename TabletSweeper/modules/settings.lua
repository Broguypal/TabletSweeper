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
    zoom_px   = 256,
    colors = {
        unseen = {r = 10, g = 10, b = 14},
        seen   = {r = 58, g = 96,  b = 68},
        panel  = {r = 12, g = 12, b = 18},
        border = {r = 70, g = 78, b = 96},
        button = {r = 38, g = 42, b = 54},
        button_hot = {r = 62, g = 72, b = 92},
        danger = {r = 130, g = 38, b = 40},
    },
}

local settings = config.load(defaults)

return settings
