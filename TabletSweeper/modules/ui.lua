local texts    = require('texts')
local util     = require('modules/util')
local settings = require('modules/settings')
local grid     = require('modules/grid')
local storage  = require('modules/storage')
local render   = require('modules/render')

local ui = {}

local TITLE_H, BAR_H, PAD = 20, 20, 6

local BTN = {}
for i = 1, 10 do BTN[i] = 'ts_btn_' .. i end
local TITLEBAR = 'ts_titlebar'

local inited, layout, hits = false, nil, {}
local confirm, dirty, drag, hot = false, true, nil, nil
local T = {}

local function commas(n)
    local s = tostring(math.floor(n))
    return ((s:reverse():gsub('(%d%d%d)', '%1,')):reverse():gsub('^,', ''))
end

local function mktext(size, bold)
    return texts.new('', {
        pos = {x = 0, y = 0},
        text = {font = 'Consolas', size = size or 9, alpha = 255,
                red = 235, green = 235, blue = 235, bold = bold or false,
                stroke = {width = 1, alpha = 200, red = 0, green = 0, blue = 0}},
        bg = {visible = false},
        flags = {draggable = false},
        padding = 0,
    })
end

function ui.init()
    if inited then return end
    render.init()
    render.new_solid(TITLEBAR)
    for i = 1, #BTN do render.new_solid(BTN[i]) end
    T.title, T.status, T.warn = mktext(10, true), mktext(9), mktext(9)
    T.labels = {}
    for i = 1, #BTN do T.labels[i] = mktext(9) end
    inited = true
end

function ui.destroy()
    if not inited then return end
    pcall(windower.prim.delete, TITLEBAR)
    for i = 1, #BTN do pcall(windower.prim.delete, BTN[i]) end
    for _, t in pairs(T) do
        if type(t) == 'table' and t.destroy then t:destroy()
        elseif type(t) == 'table' then
            for _, t2 in ipairs(t) do if t2.destroy then t2:destroy() end end
        end
    end
    inited = false
end

function ui.mark_dirty() dirty = true end

function ui.relayout()
    layout, dirty = nil, true
    render.invalidate()
end

function ui.rebuild_static()
    render.invalidate()
    ui.relayout()
end

local function clamp_pos(w, h)
    local ws = windower.get_windower_settings()
    if not ws then return end
    local sw = math.min(ws.x_res or 9999, ws.ui_x_res or 9999)
    local sh = math.min(ws.y_res or 9999, ws.ui_y_res or 9999)
    settings.pos.x = util.clamp(settings.pos.x, 0, math.max(0, sw - w))
    settings.pos.y = util.clamp(settings.pos.y, 0, math.max(0, sh - h))
end

local function build_layout()
    local v = settings.view
    local w = v + PAD * 2
    clamp_pos(w, settings.collapsed and TITLE_H
                 or (TITLE_H + PAD + v + 4 + BAR_H + PAD))
    local x, y = settings.pos.x, settings.pos.y
    local L = {x = x, y = y, w = w, title = {x = x, y = y, w = w, h = TITLE_H}}
    if settings.collapsed then
        L.h = TITLE_H
    else
        L.map = {x = x + PAD, y = y + TITLE_H + PAD, w = v, h = v}
        L.bar = {x = x + PAD, y = y + TITLE_H + PAD + v + 4, w = v, h = BAR_H}
        L.h   = TITLE_H + PAD + v + 4 + BAR_H + PAD
    end
    layout = L
    render.set_rect(L.map)
    return L
end

local function compute_hits()
    local L = layout or build_layout()
    local state = _G.TS_STATE
    local out = {}
    out[#out+1] = {x = L.x + L.w - PAD - 20, y = L.y + 3, w = 20, h = 14, action = 'collapse'}
    if settings.collapsed then return out, L end
    local b = L.bar
    if confirm then
        out[#out+1] = {x = b.x,       y = b.y, w = 108, h = BAR_H - 2, action = 'reset_yes', danger = true}
        out[#out+1] = {x = b.x + 112, y = b.y, w = 60,  h = BAR_H - 2, action = 'reset_no'}
    else
        out[#out+1] = {x = b.x,       y = b.y, w = 24, h = BAR_H - 2, action = 'zoom_out'}
        out[#out+1] = {x = b.x + 26,  y = b.y, w = 24, h = BAR_H - 2, action = 'zoom_in'}
        out[#out+1] = {x = b.x + 54,  y = b.y, w = 52, h = BAR_H - 2, action = 'reset_ask'}
        out[#out+1] = {x = b.x + 110, y = b.y, w = 62, h = BAR_H - 2, action = 'pause'}
    end
    return out, L
end

local function label_for(action, state)
    if action == 'collapse'  then return settings.collapsed and '+' or '-' end
    if action == 'reset_yes' then return 'ERASE THIS ZONE' end
    if action == 'reset_no'  then return 'Cancel' end
    if action == 'zoom_out'  then return '-' end
    if action == 'zoom_in'   then return '+' end
    if action == 'reset_ask' then return 'Reset' end
    if action == 'pause'     then return (state and state.paused) and 'Resume' or 'Pause' end
    return '?'
end

local btn_used = 0

local function button(x, y, w, h, label, action, danger)
    btn_used = btn_used + 1
    if btn_used > #BTN then return end
    local name = BTN[btn_used]
    local col = danger and settings.colors.danger
                or (hot == action and settings.colors.button_hot or settings.colors.button)
    render.place(name, x, y, w, h)
    render.tint(name, col, 235)
    windower.prim.set_visibility(name, true)
    local t = T.labels[btn_used]
    t:pos(x + 5, y + (h - 13) / 2)
    t:text(label)
    t:show()
    hits[#hits + 1] = {x = x, y = y, w = w, h = h, action = action}
end

local function finish_buttons()
    for i = btn_used + 1, #BTN do
        windower.prim.set_visibility(BTN[i], false)
        T.labels[i]:hide()
    end
end

function ui.update(me)
    ui.init()
    local state = _G.TS_STATE
    local L = layout or build_layout()

    render.update_bg({x = L.x, y = L.y, w = L.w, h = L.h})
    render.place(TITLEBAR, L.title.x, L.title.y, L.title.w, L.title.h)
    render.tint(TITLEBAR, settings.colors.border, 210)
    windower.prim.set_visibility(TITLEBAR, true)

    T.title:pos(L.x + PAD, L.y + 4)
    T.title:text('TabletSweeper - ' .. tostring(state and state.zone_name or '?'))
    T.title:show()

    btn_used, hits = 0, {}
    local rects = compute_hits()
    for _, rc in ipairs(rects) do
        if settings.collapsed and rc.action ~= 'collapse' then
            -- skip
        else
            button(rc.x, rc.y, rc.w, rc.h, label_for(rc.action, state), rc.action, rc.danger)
        end
    end

    if settings.collapsed then
        render.hide_map()
        T.status:hide(); T.warn:hide()
        finish_buttons()
        return
    end

    render.update(me.x, me.y, dirty)
    dirty = false

    local b = L.bar
    if not confirm then
        T.status:pos(b.x + 178, b.y + 3)
        T.status:text(settings.zoom_span .. 'y  ' .. commas(grid.count) .. ' cells')
        T.status:show()
    end

    local msg, col
    if render.error then
        msg, col = render.error, {255, 150, 150}
    elseif render.desc and not render.art then
        msg, col = 'no readable map image for this zone', {255, 150, 150}
    elseif state and state.paused then
        msg, col = 'recording paused', {255, 210, 90}
    end
    if msg then
        T.warn:pos(L.x + PAD, L.y + TITLE_H + PAD - 1)
        T.warn:text(msg)
        T.warn:color(col[1], col[2], col[3])
        T.warn:show()
    else
        T.warn:hide()
    end

    finish_buttons()
end

function ui.hide_all()
    if not inited then return end
    render.hide_all()
    windower.prim.set_visibility(TITLEBAR, false)
    for i = 1, #BTN do
        windower.prim.set_visibility(BTN[i], false)
        T.labels[i]:hide()
    end
    T.title:hide(); T.status:hide(); T.warn:hide()
    confirm = false
end


function ui.set_zoom(v)
    v = util.clamp(v, settings.zoom_min, settings.zoom_max)
    v = util.round(v / 25) * 25
    v = util.clamp(v, settings.zoom_min, settings.zoom_max)
    settings.zoom_span = v
    settings:save()
    ui.rebuild_static()
    return v
end

function ui.zoom(dir)
    local step = settings.zoom_step
    return ui.set_zoom(settings.zoom_span - dir * step)
end


local function inside(r, x, y)
    return r and x >= r.x and y >= r.y and x <= r.x + r.w and y <= r.y + r.h
end

local function do_action(action)
    local state = _G.TS_STATE
    if action == 'collapse' then
        settings.collapsed = not settings.collapsed
        settings:save(); confirm = false; ui.relayout()
    elseif action == 'zoom_in' then ui.zoom(1)
    elseif action == 'zoom_out' then ui.zoom(-1)
    elseif action == 'reset_ask' then confirm = true; ui.mark_dirty()
    elseif action == 'reset_no' then confirm = false; ui.mark_dirty()
    elseif action == 'reset_yes' then
        if state and state.zone then
            grid.clear()
            storage.rewrite(state.zone)
            state.last_mark_x = nil
            util.msg('swept data cleared for ' .. tostring(state.zone_name))
        end
        confirm = false
        ui.mark_dirty()
    elseif action == 'pause' then
        if state then
            state.paused = not state.paused
            util.msg('recording ' .. (state.paused and 'PAUSED' or 'resumed'))
        end
        ui.mark_dirty()
    end
end

windower.register_event('mouse', function(mtype, x, y, delta, blocked)
    if blocked or not inited then return false end
    local state = _G.TS_STATE

    if not state or not state.tracked then return false end

    local rects, L = compute_hits()
    if not L then return false end
    local panel = {x = L.x, y = L.y, w = L.w, h = L.h}

    if mtype == 0 then
        if drag then
            settings.pos.x = util.round(x - drag.dx)
            settings.pos.y = util.round(y - drag.dy)
            ui.relayout()
            return true
        end
        local over = nil
        for _, rc in ipairs(rects) do
            if inside(rc, x, y) then over = rc.action end
        end
        if over ~= hot then hot = over; ui.mark_dirty() end
        return inside(panel, x, y)
    end

    if delta and delta ~= 0 and not settings.collapsed and inside(L.map, x, y) then
        ui.zoom(delta > 0 and 1 or -1)
        return true
    end

    if mtype == 1 then
        for _, rc in ipairs(rects) do
            if inside(rc, x, y) then return true end
        end
        if inside(L.title, x, y) then
            drag = {dx = x - L.x, dy = y - L.y}
            return true
        end
        return inside(panel, x, y)
    end

    if mtype == 2 then
        if drag then drag = nil; settings:save(); return true end
        for _, rc in ipairs(rects) do
            if inside(rc, x, y) then do_action(rc.action) return true end
        end
        if inside(panel, x, y) then
            if confirm then confirm = false; ui.mark_dirty() end
            return true
        end
        return false
    end

    return false
end)

return ui
