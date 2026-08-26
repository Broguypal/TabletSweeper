local util     = require('modules/util')
local imgio    = require('modules/imgio')
local mapini   = require('modules/mapini')

-- Transform is Mappy's: Translate() works in a 256-unit space, so px scales by
-- img/256 (their Bounds halves 512/scale, "factor of 2"). Holds for any image
-- size, which is why the 512 gifs and 2048 pngs both land correctly.
local mapdata = {}

local MAPS  = 'maps/'
local CACHE = 'cache/'

-- No .gif: D3DX has no GIF loader, so a gif can never go on a prim.
local TEX_EXT      = {'.png', '.bmp', '.tga', '.jpg', '.dds'}
-- Zoom pane composites per pixel; Lua can't decode png, hence a bmp copy.
local PIXEL_EXT    = {'.bmp', '.tga'}
local UNUSABLE_EXT = {'.gif'}

function mapdata.init()
    util.ensure_dir('maps')
    util.ensure_dir('cache')
    mapini.load(windower.addon_path .. MAPS .. 'map.ini')
    return mapini.loaded
end


function mapdata.basename(zone_id, map_id)
    return string.format('%02X_%d', zone_id, map_id)
end


-- Windows is case-insensitive but packs mix 6A_0 and 6a_0, so try both.
local function find(dirs, base, exts)
    local names = {base, base:lower()}
    for _, dir in ipairs(dirs) do
        for _, e in ipairs(exts) do
            for _, n in ipairs(names) do
                local p = windower.addon_path .. dir .. n .. e
                if util.file_exists(p) then return p end
            end
        end
    end
    return nil
end


function mapdata.resolve(zone_id, x, y, z)
    if not mapini.loaded then
        return nil, mapini.error or 'map.ini not loaded'
    end

    local zone = mapini.zone(zone_id)
    if not zone then
        return nil, string.format('zone %02X is not in map.ini', zone_id)
    end

    local m, in_range = mapini.pick(zone_id, x, y, z)
    if not m then return nil, 'no map defined for this zone' end

    local base = mapdata.basename(zone_id, m.id)

    local tex = find({MAPS, CACHE}, base, TEX_EXT)
    if not tex then
        if find({MAPS}, base, UNUSABLE_EXT) then
            return nil, base .. ' is a GIF, which DirectX cannot load'
        end
        return nil, 'missing image ' .. base .. '.png in TabletSweeper/maps/'
    end

    local w, h, derr = imgio.dimensions(tex)
    if not w then
        return nil, 'could not read ' .. base .. ': ' .. tostring(derr)
    end

    -- The bmp copy is sampled in world space, so it may be any resolution;
    -- give it its own transform rather than assuming it matches the texture.
    local pixel_path = find({CACHE, MAPS}, base, PIXEL_EXT)
    local pw, ph
    if pixel_path then
        pw, ph = imgio.dimensions(pixel_path)
        if not pw then pixel_path = nil end
    end

    return {
        zone_id  = zone_id,
        map_id   = m.id,
        base     = base,
        texture  = tex,
        pixel    = pixel_path,
        w        = w,
        h        = h,
        in_range = in_range,
        ax = m.xs * w / 256,
        bx = m.xo * w / 256,
        ay = m.ys * h / 256,
        by = m.yo * h / 256,
        pw  = pw,
        ph  = ph,
        pax = pw and m.xs * pw / 256 or nil,
        pbx = pw and m.xo * pw / 256 or nil,
        pay = ph and m.ys * ph / 256 or nil,
        pby = ph and m.yo * ph / 256 or nil,
    }
end

function mapdata.still_valid(desc, zone_id, x, y, z)
    if not desc or desc.zone_id ~= zone_id then return false end
    local zone = mapini.zone(zone_id)
    if not zone or zone.count <= 1 then return true end   -- nothing to switch to
    local m = mapini.pick(zone_id, x, y, z)
    return m ~= nil and m.id == desc.map_id
end

function mapdata.px_to_world(desc, px, py)
    return (px - desc.bx) / desc.ax, (py - desc.by) / desc.ay
end




return mapdata
