local res   = require('resources')
local util  = require('modules/util')

local zones = {}

local TRACKED_NAMES = {
    'West Ronfaure',
    'East Ronfaure',
    'La Theine Plateau',
    'Valkurm Dunes',
    'Konschtat Highlands',
    'Jugner Forest',
    'Batallia Downs',
    'North Gustaberg',
    'South Gustaberg',
    'Pashhow Marshlands',
    'Rolanberry Fields',
    'West Sarutabaruta',
    'East Sarutabaruta',
    'Tahrongi Canyon',
    'Buburimu Peninsula',
    'Meriphataud Mountains',
    'Sauromugue Champaign',
    'Beaucedine Glacier',
    'Xarcabard',
    'Qufim Island',
    "Behemoth's Dominion",
    "The Sanctuary of Zi'Tah",
    "Ro'Maeve",
    'Eastern Altepa Desert',
    'Western Altepa Desert',
    'Cape Teriggan',
    'Valley of Sorrows',
    'Yuhtunga Jungle',
    'Yhoator Jungle',
}

local id_to_name = {}
local name_to_id = {}
local tracked    = {}

local function build_lookup()
    for id, z in pairs(res.zones) do
        if z and z.en then
            id_to_name[id] = z.en
            if not name_to_id[z.en] or id < name_to_id[z.en] then
                name_to_id[z.en] = id
            end
        end
    end
end

local function init()
    build_lookup()
    local missing = {}
    for _, n in ipairs(TRACKED_NAMES) do
        local id = name_to_id[n]
        if id then
            tracked[id] = true
        else
            missing[#missing + 1] = n
        end
    end
    if #missing > 0 then
        util.err('could not resolve zone id for: ' .. table.concat(missing, ', '))
    end
    local wanted = {}
    for _, n in ipairs(TRACKED_NAMES) do wanted[n] = true end
    for id, name in pairs(id_to_name) do
        if wanted[name] then tracked[id] = true end
    end
end

init()

function zones.is_tracked(id)
    return id ~= nil and tracked[id] == true
end

function zones.name_of(id)
    return id_to_name[id] or ('Zone ' .. tostring(id))
end

return zones
