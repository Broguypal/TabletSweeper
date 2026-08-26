local floor, sqrt, abs = math.floor, math.sqrt, math.abs
local rep, char, concat = string.rep, string.char, table.concat
local sub, byte = string.sub, string.byte

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

local player_x, player_y = nil, nil
local fog_key, fog_map   = nil, {}

local mips     = {}
local mipjob   = nil
local mip_max  = 0

local MIN_MIP  = 24     
local MAX_MIP  = 6

local DEF_PLAYER = {r = 255, g = 48,  b = 48}
local DEF_SWEEP  = {r = 255, g = 214, b = 64}

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

local function drop_mips()
    mips, mipjob, mip_max = {}, nil, 0
end

function render.unload_zone()
    render.desc, render.art, render.error = nil, nil, nil
    drop_mips()
    last_key = nil
    player_x, player_y = nil, nil
end

local function queue_next()
    local have = 0
    for i = 1, mip_max do
        if mips[i] then have = i else break end
    end
    if have >= mip_max or not mips[have] then return end
    mipjob = imgio.reduce_job(mips[have])
    if mipjob then mipjob.level = have + 1 else mip_max = have end
end

local function plan_mips(img)
    mips, mipjob = {[0] = img}, nil
    mip_max = 0
    local w, h = img.w, img.h
    while mip_max < MAX_MIP and floor(w / 2) >= MIN_MIP and floor(h / 2) >= MIN_MIP do
        w, h = floor(w / 2), floor(h / 2)
        mip_max = mip_max + 1
    end
    queue_next()
end

function render.pump(budget)
    if not mipjob then return end
    local ok, done = pcall(mipjob.run, mipjob, budget or 0.003)
    if not ok then
        mip_max, mipjob = mipjob.level - 1, nil
        return
    end
    if done then
        if mipjob.result then
            mips[mipjob.level] = mipjob.result
            last_key = nil 
        else
            mip_max = mipjob.level - 1
        end
        mipjob = nil
        queue_next()
    end
end

local function level_image(want)
    local have = 0
    for i = 1, want do
        if mips[i] then have = i else break end
    end
    return mips[have], have
end

function render.bind(zone_id, x, y, z)
    if mapdata.still_valid(render.desc, zone_id, x, y, z) then return true end

    local desc, err = mapdata.resolve(zone_id, x, y, z)
    if not desc then
        render.desc, render.art, render.error = nil, nil, err
        drop_mips()
        last_key = nil
        return false
    end

    render.error, render.desc, render.art = nil, desc, nil
    drop_mips()
    last_key = nil

    if desc.pixel then
        local img, ierr = imgio.load(desc.pixel)
        if img and img.w == desc.pw and img.h == desc.ph then
            render.art = img
            plan_mips(img)
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
    local s = settings.zoom_px or 256
    if s < 128 then s = 128 elseif s > 1024 then s = 1024 end
    local p = 128
    while p < 1024 and s / p > p * 2 / s do p = p * 2 end   -- nearest of 128/256/512/1024
    return p
end
render.texture_size = texture_size

local function put(mods, S, u, v, c)
    u = floor(u + 0.5)
    v = floor(v + 0.5)
    if u < 0 or v < 0 or u >= S or v >= S then return end
    local row = mods[v]
    if not row then row = {} mods[v] = row end
    row[u] = c
end

local function ring(mods, S, u0, v0, r, c)
    if r < 1 then return end
    local r2 = r * r

    for v = floor(v0 - r) - 1, floor(v0 + r) + 1 do
        local dy = v - v0
        local t = r2 - dy * dy
        if t >= 0 then
            local dx = sqrt(t)
            put(mods, S, u0 - dx, v, c)
            put(mods, S, u0 + dx, v, c)
        end
    end

    for u = floor(u0 - r) - 1, floor(u0 + r) + 1 do
        local dx = u - u0
        local t = r2 - dx * dx
        if t >= 0 then
            local dy = sqrt(t)
            put(mods, S, u, v0 - dy, c)
            put(mods, S, u, v0 + dy, c)
        end
    end
end

local function disc(mods, S, u0, v0, r, c)
    local r2 = r * r
    for v = floor(v0 - r) - 1, floor(v0 + r) + 1 do
        local dv = v - v0
        for u = floor(u0 - r) - 1, floor(u0 + r) + 1 do
            local du = u - u0
            if du * du + dv * dv <= r2 then put(mods, S, u, v, c) end
        end
    end
end

local function apply_mods(rows, mods)
    for v, cols in pairs(mods) do
        local row = rows[v + 1]
        if row then
            local idx, ni = {}, 0
            for u in pairs(cols) do ni = ni + 1 idx[ni] = u end
            table.sort(idx)
            local parts, n, pos = {}, 0, 1
            for i = 1, ni do
                local u   = idx[i]
                local off = u * 3 + 1
                if off > pos then n = n + 1 parts[n] = sub(row, pos, off - 1) end
                n = n + 1
                parts[n] = cols[u]
                pos = off + 3
            end
            n = n + 1
            parts[n] = sub(row, pos)
            rows[v + 1] = concat(parts)
        end
    end
end

local GB, GS = grid.BIAS, grid.SPAN

local function build(px, py)
    local S    = texture_size()
    local span = settings.zoom_span
    local cell = grid.cell
    local d    = render.desc

    local step = span / S

    local art, lvl = nil, 0
    if render.art and d and d.pax then
        local scale = step * abs(d.pax)
        local want  = 0
        while want < mip_max and scale >= 2 do scale, want = scale * 0.5, want + 1 end
        art, lvl = level_image(want)
    end

    local use_art = art ~= nil
    local shrink  = 2 ^ lvl
    local lax, lbx, lay, lby
    local adata, adata_off, arowsize, apix, aflip, aw, ah
    if use_art then
        lax, lbx = d.pax / shrink, d.pbx / shrink
        lay, lby = d.pay / shrink, d.pby / shrink
        adata, adata_off = art.data, art.data_off
        arowsize, apix   = art.rowsize, art.pixbytes
        aflip, aw, ah    = art.flip, art.w, art.h
    end

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
            su = floor(lax * wx + lbx)
            if su < 0 or su >= aw then su = -1 end
        end
        local r = runs[nr]
        if r and r.cx == cx and r.su == su then r.n = r.n + 1
        else
            nr = nr + 1
            runs[nr] = {
                cx = cx, su = su, n = 1,
                kb = (cx + GB) * GS,
                so = (su >= 0) and su * apix or -1, 
            }
        end
    end

    local cu, cs = settings.colors.unseen, settings.colors.seen
    local fogp  = char(cu.b or 0, cu.g or 0, cu.r or 0)
    local seenp = char(cs.b or 0, cs.g or 0, cs.r or 0)

    local fa = settings.fog_alpha or 0.6
    if fa < 0 then fa = 0 elseif fa > 1 then fa = 1 end

    local fk = concat({cu.r or 0, cu.g or 0, cu.b or 0, fa}, ':')
    if fk ~= fog_key then fog_key, fog_map = fk, {} end

    local inv = 1 - fa
    local fb, fg, fr = (cu.b or 0) * fa, (cu.g or 0) * fa, (cu.r or 0) * fa

    local function mix(p)
        local m = fog_map[p]
        if not m then
            local b, g, r = byte(p, 1, 3)
            if not r then return fogp end
            m = char(floor(b * inv + fb), floor(g * inv + fg), floor(r * inv + fr))
            fog_map[p] = m
        end
        return m
    end

    local seen = grid.seen
    local rows, cache = {}, {}
    for v = 0, S - 1 do
        local wy = y0 + sy * (v + 0.5) * step
        local cy = floor(wy / cell)
        local sv = -1
        if use_art then
            sv = floor(lay * wy + lby)
            if sv < 0 or sv >= ah then sv = -1 end
        end

        local ck = cy * 131072 + sv
        local row = cache[ck]
        if not row then
            local ro = 0
            if sv >= 0 then
                ro = adata_off + (aflip and (ah - 1 - sv) or sv) * arowsize
            end
            local ky = cy + GB
            local parts = {}
            for i = 1, nr do
                local r = runs[i]
                local p
                if sv >= 0 and r.so >= 0 then
                    local o = ro + r.so
                    p = sub(adata, o + 1, o + 3)
                    if not seen[r.kb + ky] then p = mix(p) end
                elseif seen[r.kb + ky] then
                    p = seenp
                else
                    p = fogp
                end
                parts[i] = (r.n == 1) and p or rep(p, r.n)
            end
            row = concat(parts)
            cache[ck] = row
        end
        rows[v + 1] = row
    end

    if player_x and player_y then
        local pu = (player_x - x0) / (sx * step) - 0.5
        local pv = (player_y - y0) / (sy * step) - 0.5
        local rr = grid.radius / step

        local ms = S / 256

        local cw = settings.colors.sweep  or DEF_SWEEP
        local cp = settings.colors.player or DEF_PLAYER
        local ringp = char(cw.b or 0, cw.g or 0, cw.r or 0)
        local dotp  = char(cp.b or 0, cp.g or 0, cp.r or 0)

        local mods = {}
        local thick = floor(ms + 0.5)
        if thick < 1 then thick = 1 end
        for t = 0, thick - 1 do ring(mods, S, pu, pv, rr - t * 0.7, ringp) end
        disc(mods, S, pu, pv, util.clamp(rr * 0.12, 1.5 * ms, 3.0 * ms), dotp)
        apply_mods(rows, mods)
    end

    return rows, S, S
end

local function swap(px, py, force)
    local S, span = texture_size(), settings.zoom_span
    local stepq = span / S
    local key = table.concat({
        floor(px / stepq), floor(py / stepq),
        floor((player_x or 0) / stepq), floor((player_y or 0) / stepq),
        grid.count, S, span, grid.radius,
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

    player_x, player_y = px, py

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
