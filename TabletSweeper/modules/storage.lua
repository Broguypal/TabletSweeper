local util = require('modules/util')
local grid = require('modules/grid')

local storage = {}

local function char_folder()
    local p = windower.ffxi.get_player()
    return 'data/' .. util.safe_filename((p and p.name) or 'Unknown')
end

local function path_for(zone_id)
    return windower.addon_path .. char_folder() .. '/' .. tostring(zone_id) .. '.txt'
end

local function header()
    return string.format('TSF2 %.3f\n', grid.cell)
end

function storage.rewrite(zone_id)
    if not zone_id then return end
    util.ensure_dir(char_folder())
    local f = io.open(path_for(zone_id), 'w')
    if not f then util.err('could not write save file') return end
    f:write(header())
    local buf, n = {}, 0
    for k in pairs(grid.seen) do
        local cx, cy = grid.unkey(k)
        n = n + 1; buf[n] = cx .. ',' .. cy
        if n >= 2000 then f:write(table.concat(buf, ';'), ';') buf, n = {}, 0 end
    end
    if n > 0 then f:write(table.concat(buf, ';'), ';') end
    f:close()
    grid.pending = {}
    grid.dirty = false
end

function storage.flush(zone_id)
    if not zone_id then return end
    local p = grid.pending
    if #p == 0 then grid.dirty = false return end

    util.ensure_dir(char_folder())
    local path = path_for(zone_id)
    local exists = util.file_exists(path)
    local f = io.open(path, 'a')
    if not f then util.err('could not append to save file') return end
    if not exists then f:write(header()) end

    local buf, n = {}, 0
    for i = 1, #p, 2 do
        n = n + 1; buf[n] = p[i] .. ',' .. p[i + 1]
        if n >= 2000 then f:write(table.concat(buf, ';'), ';') buf, n = {}, 0 end
    end
    if n > 0 then f:write(table.concat(buf, ';'), ';') end
    f:close()
    grid.pending = {}
    grid.dirty = false
end

storage.save = storage.flush

function storage.load(zone_id)
    grid.clear_silent()
    if not zone_id then return end

    local f = io.open(path_for(zone_id), 'r')
    if not f then grid.changed = true return end
    local body = f:read('*a')
    f:close()
    if not body or body == '' then grid.changed = true return end

    local ver, cell = body:match('^TSF(%d)%s+([%d%.]+)')
    if not ver then
        util.err('unreadable save for zone ' .. tostring(zone_id) .. ', starting fresh.')
        grid.changed = true
        return
    end
    if math.abs(tonumber(cell) - grid.cell) > 0.001 then
        util.msg('grid resolution changed since this zone was saved; starting fresh.')
        grid.changed = true
        return
    end

    for cx, cy in body:gmatch('(-?%d+),(-?%d+)') do
        grid.add(tonumber(cx), tonumber(cy))
    end
    grid.pending = {}
    grid.dirty   = false
    grid.changed = true
end

function storage.clear_all()
    local dir = windower.addon_path .. char_folder()
    local removed = 0

    local ok, list = pcall(function()
        return windower.get_dir and windower.get_dir(dir)
    end)

    if ok and type(list) == 'table' then
        for _, name in ipairs(list) do
            if type(name) == 'string' and name:match('^%-?%d+%.txt$') then
                if os.remove(dir .. '/' .. name) then removed = removed + 1 end
            end
        end
    end

    grid.clear()
    grid.pending = {}
    grid.dirty   = false

    return removed
end

return storage
