local sub, byte, char, rep = string.sub, string.byte, string.char, string.rep
local floor = math.floor

local imgio = {}

local function u16(s, i)
    local a, b = byte(s, i, i + 1)
    return a + b * 256
end

local function u32(s, i)
    local a, b, c, d = byte(s, i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function i32(s, i)
    local v = u32(s, i)
    if v >= 2147483648 then v = v - 4294967296 end
    return v
end

local function le16(v)
    v = v % 65536
    return char(v % 256, floor(v / 256))
end

local Image = {}
Image.__index = Image

function Image:px3(x, y)
    local row = self.flip and (self.h - 1 - y) or y
    local off = self.data_off + row * self.rowsize + x * self.pixbytes
    return sub(self.data, off + 1, off + 3)
end

function Image:in_bounds(x, y)
    return x >= 0 and y >= 0 and x < self.w and y < self.h
end

local function read_bmp(data)
    if #data < 54 then return nil, 'file too small' end

    local data_off = u32(data, 11)
    local w        = i32(data, 19)
    local h        = i32(data, 23)
    local bpp      = u16(data, 29)
    local comp     = u32(data, 31)

    if comp ~= 0 and comp ~= 3 then
        return nil, 'compressed BMP is not supported (save as 24-bit uncompressed)'
    end
    if bpp ~= 24 and bpp ~= 32 then
        return nil, 'BMP must be 24 or 32 bit (got ' .. bpp .. ')'
    end

    local flip = h > 0            -- positive height means bottom-up rows
    h = math.abs(h)
    if w <= 0 or h <= 0 then return nil, 'bad dimensions' end

    local pixbytes = bpp / 8
    local rowsize  = floor((bpp * w + 31) / 32) * 4

    if data_off + rowsize * h > #data then
        return nil, 'truncated pixel data'
    end

    return setmetatable({
        data = data, w = w, h = h,
        pixbytes = pixbytes, rowsize = rowsize,
        data_off = data_off, flip = flip,
        format = 'bmp',
    }, Image)
end

local function read_tga(data)
    if #data < 18 then return nil, 'file too small' end

    local idlen    = byte(data, 1)
    local cmaptype = byte(data, 2)
    local dtype    = byte(data, 3)
    local cmaplen  = u16(data, 6)
    local cmapdep  = byte(data, 8)
    local w        = u16(data, 13)
    local h        = u16(data, 15)
    local bpp      = byte(data, 17)
    local desc     = byte(data, 18)

    if dtype ~= 2 then
        return nil, 'only uncompressed true-colour TGA is supported (no RLE)'
    end
    if bpp ~= 24 and bpp ~= 32 then
        return nil, 'TGA must be 24 or 32 bit'
    end

    local data_off = 18 + idlen
    if cmaptype == 1 then
        data_off = data_off + cmaplen * floor(cmapdep / 8)
    end

    local pixbytes = bpp / 8
    local rowsize  = w * pixbytes
    local top_down = (desc % 64) >= 32      -- bit 5

    if data_off + rowsize * h > #data then
        return nil, 'truncated pixel data'
    end

    return setmetatable({
        data = data, w = w, h = h,
        pixbytes = pixbytes, rowsize = rowsize,
        data_off = data_off, flip = not top_down,
        format = 'tga',
    }, Image)
end

function imgio.load(path)
    local f = io.open(path, 'rb')
    if not f then return nil, 'file not found' end
    local data = f:read('*a')
    f:close()
    if not data or #data < 18 then return nil, 'empty file' end

    if sub(data, 1, 2) == 'BM' then
        return read_bmp(data)
    end
    return read_tga(data)
end

function imgio.dimensions(path)
    local f = io.open(path, 'rb')
    if not f then return nil, 'file not found' end
    local head = f:read(64)
    f:close()
    if not head or #head < 16 then return nil, 'file too small' end

    if sub(head, 1, 8) == '\137PNG\r\n\26\n' then
        if sub(head, 13, 16) ~= 'IHDR' then return nil, 'malformed PNG' end
        local a, b, c, d = byte(head, 17, 20)
        local e, g, i, j = byte(head, 21, 24)
        return a * 16777216 + b * 65536 + c * 256 + d,
               e * 16777216 + g * 65536 + i * 256 + j
    end

    if sub(head, 1, 3) == 'GIF' then
        return u16(head, 7), u16(head, 9)
    end

    if sub(head, 1, 2) == 'BM' then
        local w, h = i32(head, 19), i32(head, 23)
        return w, math.abs(h)
    end

    if byte(head, 1) == 0xFF and byte(head, 2) == 0xD8 then
        local jf = io.open(path, 'rb')
        local d = jf:read('*a')
        jf:close()
        local i = 3
        while i < #d - 8 do
            if byte(d, i) ~= 0xFF then i = i + 1
            else
                local m = byte(d, i + 1)
                if m >= 0xC0 and m <= 0xCF and m ~= 0xC4 and m ~= 0xC8 and m ~= 0xCC then
                    local a, b = byte(d, i + 6, i + 7)
                    local c, e = byte(d, i + 8, i + 9)
                    return c * 256 + e, a * 256 + b
                end
                local len = byte(d, i + 2) * 256 + byte(d, i + 3)
                i = i + 2 + len
            end
        end
        return nil, 'could not find JPEG frame header'
    end

    local dtype = byte(head, 3)
    if dtype == 1 or dtype == 2 or dtype == 3 or dtype == 9 or dtype == 10 or dtype == 11 then
        return u16(head, 13), u16(head, 15)
    end

    return nil, 'unrecognised image format'
end

function imgio.write_tga(path, w, h, rows, bpp)
    bpp = bpp or 24
    local desc = (bpp == 32) and 0x28 or 0x20   -- top-left origin (+8 alpha bits)
    local header = char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                   .. le16(w) .. le16(h) .. char(bpp, desc)

    local f = io.open(path, 'wb')
    if not f then return false, 'cannot open ' .. path .. ' for writing' end
    f:write(header)
    f:write(table.concat(rows))
    f:close()
    return true
end

function imgio.write_white(path)
    local row = rep(char(255, 255, 255), 2)
    return imgio.write_tga(path, 2, 2, {row, row}, 24)
end

return imgio
