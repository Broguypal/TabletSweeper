local util = {}

local CHAT_COLOR = 207
local ERR_COLOR  = 167

function util.msg(s)
    windower.add_to_chat(CHAT_COLOR, '[TabletSweeper] ' .. tostring(s))
end

function util.err(s)
    windower.add_to_chat(ERR_COLOR, '[TabletSweeper] ' .. tostring(s))
end

function util.file_exists(path)
    local f = io.open(path, 'rb')
    if f then f:close() return true end
    return false
end

function util.ensure_dir(rel)
    local abs = windower.addon_path .. rel
    if windower.dir_exists and windower.dir_exists(abs) then return true end
    if windower.create_dir then
        local ok = pcall(windower.create_dir, abs)
        if ok then return true end
    end
    local ok = pcall(function()
        local files = require('files')
        local f = files.new(rel .. '/.keep', true)
        f:write('')
    end)
    return ok
end

function util.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function util.round(v)
    return math.floor(v + 0.5)
end

function util.safe_filename(s)
    return (tostring(s):gsub('[\\/:%*%?"<>|]', ''))
end

return util
