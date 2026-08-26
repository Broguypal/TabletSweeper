local floor, abs = math.floor, math.abs

local grid = {}

grid.cell         = 4.0
grid.radius       = 50.0
grid.conservative = true

grid.seen    = {}
grid.count   = 0
grid.pending = {}
grid.dirty   = false
grid.changed = false

local BIAS  = 16384
local SPAN  = 32768

grid.BIAS = BIAS
grid.SPAN = SPAN

local function key(cx, cy)
    return (cx + BIAS) * SPAN + (cy + BIAS)
end
grid.key = key

function grid.unkey(k)
    local cy = k % SPAN - BIAS
    local cx = floor(k / SPAN) - BIAS
    return cx, cy
end

function grid.clear_silent()
    grid.seen    = {}
    grid.count   = 0
    grid.pending = {}
end

function grid.clear()
    grid.clear_silent()
    grid.dirty   = true
    grid.changed = true
end

function grid.is_seen(cx, cy)
    return grid.seen[(cx + BIAS) * SPAN + (cy + BIAS)] ~= nil
end

function grid.add(cx, cy)
    local k = (cx + BIAS) * SPAN + (cy + BIAS)
    if not grid.seen[k] then
        grid.seen[k] = true
        grid.count = grid.count + 1
        return true
    end
    return false
end

function grid.mark(x, y)
    local c   = grid.cell
    local r   = grid.radius
    local r2  = r * r
    local cons = grid.conservative

    local cx0 = floor((x - r) / c)
    local cx1 = floor((x + r) / c)
    local cy0 = floor((y - r) / c)
    local cy1 = floor((y + r) / c)

    local added = 0
    local seen  = grid.seen
    local pending = grid.pending
    local np = #pending

    for cx = cx0, cx1 do
        local ax = cx * c
        local bx = ax + c
        local dx
        if cons then
            dx = (abs(ax - x) > abs(bx - x)) and (ax - x) or (bx - x)
        else
            dx = (ax + bx) * 0.5 - x
        end
        local dx2 = dx * dx
        if dx2 <= r2 then
            for cy = cy0, cy1 do
                local ay = cy * c
                local by = ay + c
                local dy
                if cons then
                    dy = (abs(ay - y) > abs(by - y)) and (ay - y) or (by - y)
                else
                    dy = (ay + by) * 0.5 - y
                end
                if dx2 + dy * dy <= r2 then
                    local k = (cx + BIAS) * SPAN + (cy + BIAS)
                    if not seen[k] then
                        seen[k] = true
                        added = added + 1
                        np = np + 1
                        pending[np] = cx
                        np = np + 1
                        pending[np] = cy
                    end
                end
            end
        end
    end

    if added > 0 then
        grid.count   = grid.count + added
        grid.dirty   = true
        grid.changed = true
    end
    return added
end

return grid
