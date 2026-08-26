local floor, sqrt, abs = math.floor, math.sqrt, math.abs
local rep, char, concat = string.rep, string.char, table.concat

local util     = require('modules/util')
local settings = require('modules/settings')
local imgio    = require('modules/imgio')
local grid     = require('modules/grid')
local mapdata  = require('modules/mapdata')

local render = {}

local P = {
    bg   = 'ts_bg',
    mapA = 'ts_map_a',
    mapB = 'ts_map_b',
}

render.desc  = nil
render.art   = nil
render.error = nil

local created  = false
local active   = 'B'
local last_key = nil
local rect     = nil
local WHITE    = 'data/white.tga'

function render.white_path() return windower.addon_path .. WHITE end

local function no_fit(name)
    pcall(windower.prim.set_fit_to_texture, name, false)
end

function render.new_solid(name)
    windower.prim.create(name)
    windower.prim.set_texture(name, render.white_path())
    no_fit(name)
    windower.prim.set_visibility(name, false)
    return name
end

function render.place(name, x, y, w, h)
    windower.prim.set_position(name, x, y)
    windower.prim.set_size(name, w, h)
end

function render.tint(name, c, a)
    windower.prim.set_color(name, a or 255, c.r or 255, c.g or 255, c.b or 255)
end

function render.init()
    if created then return end
    util.ensure_dir('data')
    if not util.file_exists(render.white_path()) then
        imgio.write_white(render.white_path())
    end
    render.new_solid(P.bg)
    for _, n in ipairs({P.mapA, P.mapB}) do
        windower.prim.create(n)
        no_fit(n)
        windower.prim.set_visibility(n, false)
    end
    created = true
end

function render.destroy()
    if not created then return end
    for _, name in pairs(P) do pcall(windower.prim.delete, name) end
    created = false
end

function render.hide_all()
    if not created then return end
    for _, name in pairs(P) do windower.prim.set_visibility(name, false) end
end

function render.hide_map()
    if not created then return end
    for _, n in ipairs({P.mapA, P.mapB}) do
        windower.prim.set_visibility(n, false)
    end
end

function render.unload_zone()
    render.desc, render.art, render.error = nil, nil, nil
    last_key = nil
end

function render.bind(zone_id, x, y, z)
    if mapdata.still_valid(render.desc, zone_id, x, y, z) then return true end

    local desc, err = mapdata.resolve(zone_id, x, y, z)
    if not desc then
        render.desc, render.art, render.error = nil, nil, err
        last_key = nil
        return false
    end

    render.error, render.desc, render.art = nil, desc, nil
    last_key = nil

    if desc.pixel then
        local img, ierr = imgio.load(desc.pixel)
        if img and img.w == desc.pw and img.h == desc.ph then
            render.art = img
        else
            util.err('could not use ' .. desc.base .. ' image data: ' .. tostring(ierr or 'size mismatch'))
        end
    else
        util.err('no readable image for ' .. desc.base .. ' - see README')
    end
    return true
end

function render.set_rect(box)
    rect = box
    last_key = nil
end

local function texture_size()
    local span = settings.zoom_span
    if span > 700 then return math.max(128, math.floor(settings.zoom_px / 2)) end
    return settings.zoom_px
end
render.texture_size = texture_size

local function build(px, py)
    local S    = texture_size()
    local span = settings.zoom_span
    local cell = grid.cell
    local d    = render.desc
    local art  = render.art
    local use_art = (art ~= nil and d ~= nil and d.pax ~= nil)

    local step = span / S

    -- YScale is negative in map.ini, so image rows run opposite to world Y.
    -- Follow the image on both axes or north/south comes out mirrored.
    local sx, sy = 1, 1
    if d then
        if d.ax < 0 then sx = -1 end
        if d.ay < 0 then sy = -1 end
    end

    local x0 = px - sx * span / 2
    local y0 = py - sy * span / 2

    local runs, nr = {}, 0
    for u = 0, S - 1 do
        local wx = x0 + sx * (u + 0.5) * step
        local cx = floor(wx / cell)
        local su = -1
        if use_art then
            su = floor(d.pax * wx + d.pbx)
            if su < 0 or su >= art.w then su = -1 end
        end
        local r = runs[nr]
        if r and r.cx == cx and r.su == su then r.n = r.n + 1
        else nr = nr + 1; runs[nr] = {cx = cx, su = su, n = 1} end
    end

    local cu, cs = settings.colors.unseen, settings.colors.seen
    local fogp  = char(cu.b or 0, cu.g or 0, cu.r or 0)
    local seenp = char(cs.b or 0, cs.g or 0, cs.r or 0)

    local rows, cache = {}, {}
    for v = 0, S - 1 do
        local wy = y0 + sy * (v + 0.5) * step
        local cy = floor(wy / cell)
        local sv = -1
        if use_art then
            sv = floor(d.pay * wy + d.pby)
            if sv < 0 or sv >= art.h then sv = -1 end
        end

        local ck = cy * 131072 + sv
        local row = cache[ck]
        if not row then
            local parts = {}
            for i = 1, nr do
                local r = runs[i]
                if not grid.is_seen(r.cx, cy) then
                    parts[i] = rep(fogp, r.n)
                elseif sv >= 0 and r.su >= 0 then
                    parts[i] = rep(art:px3(r.su, sv), r.n)
                else
                    parts[i] = rep(seenp, r.n)
                end
            end
            row = concat(parts)
            cache[ck] = row
        end
        rows[v + 1] = row
    end
    return rows, S, S
end

-- Double-buffered: write and bind the idle prim, then swap visibility. Reusing
-- one prim made it blink while the texture was recreated.
local function swap(px, py, force)
    local S, span = texture_size(), settings.zoom_span
    local stepq = span / S
    local key = table.concat({
        floor(px / stepq), floor(py / stepq), grid.count, S, span,
        render.desc and render.desc.base or '-',
    }, ':')

    if not force and key == last_key then return true end

    local target = (active == 'A') and 'B' or 'A'
    local rows, w, h = build(px, py)
    if not rows then return false end

    local path = windower.addon_path .. 'data/_map' .. target .. '.tga'
    local ok, err = imgio.write_tga(path, w, h, rows, 24)
    if not ok then util.err(tostring(err)) return false end

    local prim = (target == 'A') and P.mapA or P.mapB
    local old  = (target == 'A') and P.mapB or P.mapA
    windower.prim.set_texture(prim, path)
    no_fit(prim)
    render.place(prim, rect.x, rect.y, rect.w, rect.h)
    windower.prim.set_color(prim, 255, 255, 255, 255)
    windower.prim.set_visibility(prim, true)
    windower.prim.set_visibility(old, false)

    active, last_key = target, key
    return true
end

-- World extent of the map image.
local function map_bounds(d)
    local x0, y0 = mapdata.px_to_world(d, 0, 0)
    local x1, y1 = mapdata.px_to_world(d, d.w, d.h)
    if x0 > x1 then x0, x1 = x1, x0 end
    if y0 > y1 then y0, y1 = y1, y0 end
    return x0, x1, y0, y1
end


local function view_centre(px, py)
    local d = render.desc
    if not d then return px, py end
    local span = settings.zoom_span
    local x0, x1, y0, y1 = map_bounds(d)

    local cx
    if (x1 - x0) <= span then cx = (x0 + x1) / 2
    else cx = util.clamp(px, x0 + span / 2, x1 - span / 2) end

    local cy
    if (y1 - y0) <= span then cy = (y0 + y1) / 2
    else cy = util.clamp(py, y0 + span / 2, y1 - span / 2) end

    return cx, cy
end

function render.update(px, py, force)
    if not rect then return end

    if not render.desc or not render.art then
        render.hide_map()
        return
    end

    local cx, cy = view_centre(px, py)
    swap(cx, cy, force)
end

function render.update_bg(box)
    render.place(P.bg, box.x, box.y, box.w, box.h)
    render.tint(P.bg, settings.colors.panel, 235)
    windower.prim.set_visibility(P.bg, true)
end

function render.invalidate()
    last_key = nil
end

return render
