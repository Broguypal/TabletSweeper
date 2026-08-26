_addon.name     = 'TabletSweeper'
_addon.author   = 'Broguypal'
_addon.version  = '1.0.0'

package.path = windower.addon_path .. '?.lua;' .. package.path

require('tables')
require('strings')

local util    = require('modules/util')
local settings= require('modules/settings')
local zones   = require('modules/zones')
local grid    = require('modules/grid')
local storage = require('modules/storage')
local mapini  = require('modules/mapini')
local mapdata = require('modules/mapdata')
local render  = require('modules/render')
local ui      = require('modules/ui')

local state = {
    zone = nil, zone_name = nil,
    tracked = false, loaded = false, paused = false,
    last_tick = 0, last_save = 0,
    last_mark_x = nil, last_mark_y = nil,
}
_G.TS_STATE = state

local function unload_zone()
    if state.tracked and state.loaded then storage.rewrite(state.zone) end
    grid.clear_silent()
    render.unload_zone()
    state.loaded = false
    state.last_mark_x, state.last_mark_y = nil, nil
end

local function load_zone(zid)
    unload_zone()
    state.zone      = zid
    state.zone_name = zones.name_of(zid)
    state.tracked   = zones.is_tracked(zid)
    if not state.tracked then ui.hide_all() return end

    grid.cell         = settings.cell
    grid.radius       = settings.radius
    grid.conservative = settings.conservative

    storage.load(zid)
    state.loaded = true
    state.last_save = os.clock()
    ui.mark_dirty()
end

local function tick()
    local info = windower.ffxi.get_info()
    if not info or not info.logged_in then ui.hide_all() return end
    if info.zone ~= state.zone then load_zone(info.zone) end
    if not state.tracked then ui.hide_all() return end

    local me = windower.ffxi.get_mob_by_target('me')
    if not me or not me.x then ui.hide_all() return end

    render.bind(state.zone, me.x, me.y, me.z)

    if not state.paused then
        local lx, ly = state.last_mark_x, state.last_mark_y
        if not lx or (me.x - lx) ^ 2 + (me.y - ly) ^ 2 > 0.25 then
            if grid.mark(me.x, me.y) > 0 then ui.mark_dirty() end
            state.last_mark_x, state.last_mark_y = me.x, me.y
        end
    end

    ui.update(me)

    local now = os.clock()
    if grid.dirty and now - state.last_save > settings.autosave_seconds then
        storage.flush(state.zone)
        state.last_save = now
    end
end

windower.register_event('prerender', function()
    local now = os.clock()
    if now - state.last_tick < 1 / math.max(1, settings.update_hz) then return end
    state.last_tick = now
    local ok, err = pcall(tick)
    if not ok then
        util.err('error: ' .. tostring(err))
        ui.hide_all()
    end
end)

windower.register_event('zone change', function(new_id) load_zone(new_id) end)
windower.register_event('logout', function() unload_zone() ui.hide_all() end)
windower.register_event('login',  function() state.zone = nil end)
windower.register_event('unload', function()
    if state.tracked and state.loaded then storage.rewrite(state.zone) end
    render.destroy()
    ui.destroy()
end)

if mapdata.init() then
    util.msg('loaded.')
else
    util.err(tostring(mapini.error))
end
