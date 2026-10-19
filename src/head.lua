-- DRS Dents for any CSP server (Emperor ACSM, plain acServer): the metal of a car that took a knock is pushed in, on every screen that sees the car.
-- dents.lua is BUILT by build.js: this head + DRS_Street client/lua/DRS_Dents.lua (unchanged, the mesh work) + tail.lua. Edit the parts, never dents.lua.
-- DRS Street has a server plugin that judges the knocks. Here nobody does, so every client judges ONLY ITS OWN car (a knock it felt itself, the rules
-- of DentRules.cs for a pilot's car) and tells the others the whole list of its dents in one online event. The receiver takes the slot from the
-- sender of the event, never from the message: a client cannot dent anybody else's car. A wrong or a missing script on one client costs only the
-- dents of that client's car.
local VERSION = 'DRS Dents 1.0'

-- [SCRIPT_x] keys of the server's CSP extra options
local cfgDefaults = {
  depth = 1,      -- how deep the dents go: 1 = as on DRS Street (a pilot's car), 0.5 = half, 2 = twice
  minKmh = 14,    -- a knock with another car slower than this (the difference of the speeds) leaves nothing; a wall needs 35
}
local okCfg, cfgRead = pcall(ac.configValues, cfgDefaults)
local cfg = okCfg and cfgRead or cfgDefaults

-- ---------------------------------------------------------------- the rules (DRS Street server/DrsCore.Logic/Dents.cs, a pilot's car)
local MAX_PER_CAR, MAX_DEPTH_CM, MERGE_CM, WALL_MIN_KMH, MAX_KMH = 12, 110, 40, 35, 400
local function round(x) return math.floor(x + 0.5) end
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end

local function depthCm(kmh, wall)
  local d = clamp(4 + 30 * clamp((kmh - 14) / 86, 0, 1) ^ 1.4, 4, 34)
  if kmh > 100 then d = math.min(70, 34 + (kmh - 100) * 0.45) end
  return round(wall and d * 0.7 or d)
end

local function radiusCm(kmh)
  if kmh <= 100 then return round(clamp(34 + kmh * 0.32, 34, 66)) end
  return round(math.min(110, 66 + (kmh - 100) * 0.55))
end

--- A point inside the size of a car (cm) and a direction about 100 long, else nil.
local function makeDent(x, y, z, dx, dy, dz, kmh, wall)
  if x < -250 or x > 250 or y < -40 or y > 320 or z < -700 or z > 700 then return nil end
  local len2 = dx * dx + dy * dy + dz * dz
  if len2 < 60 * 60 or len2 > 140 * 140 then return nil end
  local k = math.min(kmh, MAX_KMH)
  local depth = math.min(round(round(round(depthCm(k, wall) * 1.5) * 0.5) * cfg.depth), MAX_DEPTH_CM)
  return { x = x, y = y, z = z, dx = clamp(dx, -127, 127), dy = clamp(dy, -127, 127), dz = clamp(dz, -127, 127), depth = depth, radius = radiusCm(k) }
end

--- Adds a dent to the list (nil = refused): at most MAX_PER_CAR, and the dents within MERGE_CM of the spot add up to at most MAX_DEPTH_CM.
local function addDent(list, d)
  if #list >= MAX_PER_CAR then return nil end
  local sum = 0
  for _, o in ipairs(list) do
    local ex, ey, ez = o.x - d.x, o.y - d.y, o.z - d.z
    if ex * ex + ey * ey + ez * ez <= MERGE_CM * MERGE_CM then sum = sum + o.depth end
  end
  local room = MAX_DEPTH_CM - sum
  if room < 3 then return nil end
  if d.depth > room then d.depth = room end
  list[#list + 1] = d
  return d
end

-- ---------------------------------------------------------------- the own car and the online event
local function newEpoch() return math.random(1, 1000000000) end   -- a new life of the car: the viewers forget the old dents
local mine = { epoch = newEpoch(), dents = {} }
local dirty = true                                                  -- the list changed (or was never told): tell it
local handlers = {}

local function deliver(body)
  local msg = '\194\167DRS:' .. body                                -- "§DRS:" + frame, as DRS_Dents.lua listens on DRS Street
  for i = 1, #handlers do
    local ok, err = pcall(handlers[i], msg, -1)
    if not ok then ac.log('[DRS Dents] ' .. tostring(err)) end
  end
end

--- A car's whole list as the frames of DRS Street: the module forgets a car's dents when the epoch changes, and skips the ids it has.
local function deliverState(slot, epoch, n, get)
  if n == 0 then deliver(string.format('DENT:RESET:%d:%d', slot, epoch)) return end
  for i = 1, n do
    local d = get(i)
    deliver(string.format('DENT:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d', slot, epoch, i, d.x, d.y, d.z, d.dx, d.dy, d.dz, d.depth, d.radius))
  end
end

local N = MAX_PER_CAR
local sendEvent, accessEvent
local function onState(sender, d)
  if not sender then return end                                     -- only the clients talk here
  local n = math.min(d.n, N)
  if d.epoch <= 0 then return end
  deliverState(sender.sessionID, d.epoch, n, function(i)
    local k = i - 1
    return { x = d.x[k], y = d.y[k], z = d.z[k], dx = d.dx[k], dy = d.dy[k], dz = d.dz[k], depth = d.depth[k], radius = d.radius[k] }
  end)
end

local okE, s, a = pcall(function()
  return ac.OnlineEvent({
    ac.StructItem.key('drsDents1'),
    epoch = ac.StructItem.int32(),
    n = ac.StructItem.uint8(),
    x = ac.StructItem.array(ac.StructItem.int16(), N),
    y = ac.StructItem.array(ac.StructItem.int16(), N),
    z = ac.StructItem.array(ac.StructItem.int16(), N),
    dx = ac.StructItem.array(ac.StructItem.int8(), N),
    dy = ac.StructItem.array(ac.StructItem.int8(), N),
    dz = ac.StructItem.array(ac.StructItem.int8(), N),
    depth = ac.StructItem.array(ac.StructItem.uint8(), N),
    radius = ac.StructItem.array(ac.StructItem.uint8(), N),
  }, onState)
end)
if okE then sendEvent, accessEvent = s, a else ac.log('[DRS Dents] online events unavailable: ' .. tostring(s)) end

local function repair()
  mine = { epoch = newEpoch(), dents = {} }
  dirty = true
end

--- "HIT:<other|->:<km/h>:<3 on the other car>:<3 its way>:<3 on mine>:<3 my way>" from DRS_Dents.lua: only the part about my own car is used.
local function hit(payload)
  local f = {}
  for v in tostring(payload):gmatch('[^:]+') do f[#f + 1] = v end
  if #f ~= 15 or f[1] ~= 'HIT' then return end
  local n = {}
  for i = 3, 15 do n[#n + 1] = tonumber(f[i]); if not n[#n] then return end end
  local wall = f[2] == '-'
  local kmh = n[1]
  if kmh < (wall and WALL_MIN_KMH or cfg.minKmh) then return end
  local d = makeDent(n[8], n[9], n[10], n[11], n[12], n[13], kmh, wall)
  if d and addDent(mine.dents, d) then dirty = true end
end

--- What DRS_Dents.lua thinks is the server.
DRS_Net = { available = okE }
function DRS_Net.onMessage(fn) handlers[#handlers + 1] = fn end
function DRS_Net.send(cmd, payload)
  if cmd ~= 'dent' then return false end
  if payload == 'REPAIR' then repair() else hit(payload) end
  return true
end

local TEXTS = {
  ['dents.repaired'] = 'Кузов відремонтовано.',
  ['dents.repair_move'] = 'Щоб відремонтувати кузов, зупини машину. У боксах це відбувається саме за 3 секунди.',
}
DRS_I18N = { t = function(key) return TEXTS[key] or key end }

local SEND_GAP = 0.3     -- the original AC server takes one message in 200 ms at most
local lastSent = -100

--- Tells the own list (and shows it here at once). The newest list is sent again by CSP to every car that connects later.
local function flush(clock)
  if not dirty or clock - lastSent < SEND_GAP then return end
  local slot = ac.getCar(0).sessionID
  if accessEvent then
    local p = accessEvent()
    p.epoch, p.n = mine.epoch, #mine.dents
    for k = 0, N - 1 do
      local d = mine.dents[k + 1] or { x = 0, y = 0, z = 0, dx = 0, dy = 0, dz = 0, depth = 0, radius = 0 }
      p.x[k], p.y[k], p.z[k], p.dx[k], p.dy[k], p.dz[k], p.depth[k], p.radius[k] = d.x, d.y, d.z, d.dx, d.dy, d.dz, d.depth, d.radius
    end
    if sendEvent(nil, true) == false then return end                -- rate limit: next frame
  end
  lastSent, dirty = clock, false
  deliverState(slot, mine.epoch, #mine.dents, function(i) return mine.dents[i] end)
end
