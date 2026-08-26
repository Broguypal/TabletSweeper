
local mapini = {}

mapini.zones  = {}
mapini.loaded = false
mapini.path   = nil
mapini.error  = nil

local function parse_line(line)
    if line == '' or line:sub(1, 1) == ';' or line:sub(1, 1) == '[' then return end

    local left, right = line:match('^([^=]+)=(.*)$')
    if not left or not right then return end

    local hex, mid = left:match('^%s*(%x+)_(%d+)%s*$')
    if not hex then return end

    local zone_id = tonumber(hex, 16)
    local map_id  = tonumber(mid)
    if not zone_id or not map_id then return end

    local semi = right:find(';', 1, true)
    if semi then right = right:sub(1, semi - 1) end

    local nums = {}
    for tok in right:gmatch('[^,]+') do
        nums[#nums + 1] = tonumber((tok:gsub('%s', '')))
    end

    if #nums < 4 then return end
    if (#nums - 4) % 6 ~= 0 then return end
    if not (nums[1] and nums[2] and nums[3] and nums[4]) then return end
    if nums[1] == 0 or nums[3] == 0 then return end

    local entry = {
        id     = map_id,
        xs     = nums[1],
        xo     = nums[2],
        ys     = nums[3],
        yo     = nums[4],
        ranges = {},
    }

    local i = 5
    while i + 5 <= #nums do
        local x1, z1, y1 = nums[i], nums[i + 1], nums[i + 2]
        local x2, z2, y2 = nums[i + 3], nums[i + 4], nums[i + 5]
        if x1 and z1 and y1 and x2 and z2 and y2 then
            entry.ranges[#entry.ranges + 1] = {
                x1 = math.min(x1, x2), x2 = math.max(x1, x2),
                y1 = math.min(y1, y2), y2 = math.max(y1, y2),
                z1 = math.min(z1, z2), z2 = math.max(z1, z2),
            }
        end
        i = i + 6
    end

    return zone_id, entry
end

function mapini.load(path)
    mapini.zones  = {}
    mapini.loaded = false
    mapini.error  = nil
    mapini.path   = path

    local f = io.open(path, 'r')
    if not f then
        mapini.error = 'map.ini not found - copy it from your Mappy map pack into TabletSweeper/maps/'
        return false
    end

    local body = f:read('*a')
    f:close()
    if not body then
        mapini.error = 'map.ini is empty'
        return false
    end

    local total = 0
    for line in body:gmatch('[^\r\n]+') do
        local zone_id, entry = parse_line(line)
        if zone_id then
            local z = mapini.zones[zone_id]
            if not z then
                z = {maps = {}, count = 0}
                mapini.zones[zone_id] = z
            end
            if not z.maps[entry.id] then      -- first definition wins, as Mappy does
                z.maps[entry.id] = entry
                z.count = z.count + 1
                total = total + 1
            end
        end
    end

    if total == 0 then
        mapini.error = 'map.ini contained no usable entries'
        return false
    end

    mapini.loaded = true
    mapini.count  = total
    return true
end

function mapini.zone(zone_id)
    return zone_id and mapini.zones[zone_id] or nil
end

function mapini.pick(zone_id, x, y, z)
    local zone = mapini.zone(zone_id)
    if not zone then return nil end

    local fallback, lowest = nil, nil
    for id, m in pairs(zone.maps) do
        if lowest == nil or id < lowest then
            lowest, fallback = id, m
        end
        for _, r in ipairs(m.ranges) do
            -- Height deliberately ignored: detection is horizontal only.
            if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then
                return m, true
            end
        end
    end
    return fallback, false
end


return mapini
