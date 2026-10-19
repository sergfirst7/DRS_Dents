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

-- ================================================================ DRS_Dents.lua of DRS Street f9d1329 (do not edit here)
;(function()
-- DRS_Dents.lua - dents on the cars (docs/DENTS.md). The metal of a car that took a knock is really pushed in, on every screen that sees the car: the traffic, the cars of the other pilots, the own one.
--   what this client does with a knock of its own car (polled every frame: collisionDepth rises):  dent HIT:<other slot|->:<km/h>:<where on the other car, cm>:<its way>:<where on mine>:<my way>
--   what the server tells (every client that can see the car; a traffic car is not one car, the server sends the dents of the instance this viewer sees):
--     DENT:<slot>:<epoch>:<id>:<x>:<y>:<z>:<dx>:<dy>:<dz>:<depth cm>:<radius cm>   a dent on the car of this slot (a new epoch = a new life of the car: forget the old dents first)
--     DENT:RESET:<slot>:<epoch>                                                      the car of this slot is whole again (repaired, gone, another instance)
--   x, y, z and dx, dy, dz are in the own coordinates of the car (+z ahead, +x to the left, y up; dx.. x 100). The script pushes the vertices of every mesh of the car (all LODs, not the wheels)
--   that are near the spot by a Gaussian bowl (a slow swell of its depth, normals leaning with the bowl), from the pristine vertices it keeps (ac.SceneReference:getVertices / alterVertices, in CSP since 0.1.80).
-- Facts of the game that this file is built on (DentLab, tools/dentlab, measured on the owner's PC with CSP 0.3.0-preview445): VertexBuffer:clone() throws "C++ exception" (every getVertices() is a
-- fresh copy: the pristine one is a second call); vb.raw[k] (0-based) reads and writes the vertex memory directly, ~100 times cheaper than get/set; alterVertices(vb) takes the same buffer again and again.
-- The cost: a car is read once (8 ms for the biggest model, 82 000 vertices), the first dent ~8 ms, every next one ~1 ms; nothing at all runs for a car without dents.
-- Everything that touches the world runs under pcall: if the meshes cannot be changed the module switches itself off and logs once (a dent must never take the game script down).
-- The dents cannot be switched off by a pilot (the owner, 2026-10-14: "the crumpling cars are a must of our server, without a switch"): the module only stops by itself on an error. "!repair" (not in any hint) makes
-- his own car new when it stands still; the repair is also asked by itself after 3 s in the pits.
local T = DRS_I18N.t
local M = {}
local function K(key) return key end -- marks a text key that is looked up later; the i18n test counts every K call as a use of the key

local RANGE_M = 170            -- a car farther than this from the camera is crumpled when it comes nearer (the dents wait in the list)
local PER_PASS = 2             -- dents made in one pass over the cars (the first of a car costs up to 8 ms, the next ones ~1 ms)
local PASS_SECONDS = 0.15      -- how often the pending dents are looked at
local KEEP_SECONDS = 90        -- the meshes of a car without dents stay read this long
local ROUGH = 0.1              -- how uneven the crushed metal is: a slow swell of the depth (0 = a smooth bowl). Never a different push for each vertex: that tore the metal into shards (the owner, 2026-10-13)
local MIN_KMH = 5              -- under this a knock is not told (the server wants 5 for a traffic car, 14 for a pilot's, a wall 35)
local WALL_KMH = 35
local REPORT_GAP = 0.35        -- seconds between two reports about the SAME car (or the wall)
local REPORT_MIN = 0.12        -- seconds between two reports of any kind
local WIDE_SLACK = 2.5         -- the game says it was a car (collidedWith) but the contact point is off the box of every car: the nearest within this is the one (a remote car is a little behind its body)
local PIT_SECONDS = 3          -- standing in the pits this long repairs the own car
local REPAIR_GAP = 10
local HISTORY = 14             -- frames of the own velocity kept (the speed before the knock)
local BEFORE_SECONDS = 0.12    -- the knock is judged by the velocities this long before it was noticed
local BOX_SLACK = 0.9          -- the point of the knock may be this far outside the box of a car and still be that car's
-- Parts that do not belong to the crumpling body, by name. Only words that are surely not the bodywork: "brake" is also a brake light, "rim" a trim, "disc" and "hub" a hubcap's cover: those
-- stayed where they were while the panel moved and stuck out of it as spikes (the owner's RX-8, 2026-10-13). The wheels, discs and calipers are held by where they are (WHEEL_CLEAR), not by name.
local SKIP = { "wheel", "tyre", "tire", "caliper", "steer", "interior", "seat", "driver", "dash", "cockpit", "leather", "carpet", "cluster", "radio", "stitching" }
-- What a dent may not do (the owner, 2026-10-13: "the wheels must stay straight, and the deformation must not go past the axis of the car"):
local WHEEL_CLEAR = 0.02           -- the metal does not move at all this close to the tyre (m, from its radius) ...
local WHEEL_FADE = 0.24            -- ... and is free again this much farther: the arch keeps its shape, the tyre never pokes through
local WHEEL_SIDE = 0.4             -- only the metal this close to the tyre across the car is held (the width of the wheel/2 + this)
local CABIN_SHARE = 0.4            -- between the axles the passenger cell is stiff: a dent there is this share of its depth ...
local CABIN_FADE = 0.45            -- ... and the share grows to 1 this far outside the axle line (crumple zones)
local AXIS_KEEP = 0.25             -- metal never crosses the middle line of the car: it stays this far from it (m)

local cars = {}                -- slot -> { epoch, dents = { { id, x, y, z, dx, dy, dz, depth, radius } ... }, applied = n, id, driver }
local labs = {}                -- car index -> the read meshes of the car
local unreadable = {}          -- car index -> the model that has no mesh this script can read (an encrypted one): not tried again
local logged = {}              -- model -> true once the log has said what was read of it
local broken, brokenWhy = false, nil
local clock, passAt = 0, 0
local lastReport, lastRepair, pitFor = -100, -100, 0
local lastFor = {}                -- slot of the other car (-1: the track) -> the clock of the last report about it
local hist = {}                -- the own velocity of the last frames
local wasIn = false            -- the own car was in a knock in the last frame

-- ---------------------------------------------------------------- the meshes of a car
local ORIGIN, FORWARD = vec3(0, 0, 0), vec3(0, 0, 1)
local BUILD_BUDGET = 0.004         -- seconds of a frame that reading the meshes of a car may take: a heavy model (a pack car of 100 MB, a million vertices) is read over many frames
local MAX_VERTS = 1500000          -- a model with more is left alone
M.buildBudget = BUILD_BUDGET       -- (a test may make it smaller)

--- A slow wave in -1..1 (a wavelength of 0.5-0.8 m): the depth of a dent swells and fades a little, the neighbours of a vertex get nearly the same push.
local function swell(x, y, z)
    return math.sin(x * 8 + z * 6) * math.sin(y * 7 + x * 5 + 1.3)
end

local function skipped(name)
    name = tostring(name or ""):lower()
    for _, s in ipairs(SKIP) do if name:find(s, 1, true) then return true end end
    return false
end

--- Does the transform of a node follow the car? A node that is not on screen (another LOD, a hidden part) may keep an old one: the vertices of its meshes would be worked out in the wrong place.
local function followsCar(world, body)
    local o1, o2 = world:transformPoint(ORIGIN), body:transformPoint(ORIGIN)
    if o1:distance(o2) > 0.4 then return false end
    local f1, f2 = world:transformVector(FORWARD), body:transformVector(FORWARD)
    return f1.x * f2.x + f1.y * f2.y + f1.z * f2.z > 0.985
end

local TEST_A, TEST_B = vec3(0.37, 1.13, -2.71), vec3(-1.9, 0.4, 0.8)
--- Two matrices that place points alike: the node is the root of the car (or sits on it without a move of its own).
local function samePlace(a, b)
    return a:transformPoint(TEST_A):distance(b:transformPoint(TEST_A)) < 1e-4 and a:transformPoint(TEST_B):distance(b:transformPoint(TEST_B)) < 1e-4
end

--- The LOCAL matrices of the nodes from a mesh up to the root of the car (the root left out), the nearest first: what the model says, never stale.
--- The world matrix of a node of a LOD that is not on screen is not kept up to date by the game (a dent landed only on the LOD that was on screen when the car was read: seen from the cockpit
--- and not from outside, the owner 2026-10-13). The root is the first node whose world matrix places points as the root's does: `countMatches` said yes at the very first node of every mesh,
--- so the turn of the model's own nodes was lost (the RX-8 and the Bogdan have their meshes under nodes turned by 90 degrees: a head-on hit crumpled the roof; a Camry's are turned by 180:
--- a hit from behind dented the nose). nil = the chain could not be walked.
local function nodeChain(ref, rootWorld)
    local list, node = {}, ref:getParent()
    for _ = 1, 40 do
        if not node then return nil end
        local w = node:getWorldTransformationRaw()
        if not w then return nil end
        if samePlace(w, rootWorld) then return list end
        local l = node:getTransformationRaw()
        if not l then return nil end
        list[#list + 1] = l
        node = node:getParent()
    end
    return nil
end

--- How a mesh maps into the car's own coordinates, as numbers: car = o + x a + y b + z c, worked out from where four points go (every step a transformPoint: no product of matrices whose
--- order could be taken the wrong way round). { ox, oy, oz, ax, ay, az, bx, by, bz, cx, cy, cz }
local function affine(place)
    local o, a, b, c = place(0, 0, 0), place(1, 0, 0), place(0, 1, 0), place(0, 0, 1)
    return { o.x, o.y, o.z, a.x - o.x, a.y - o.y, a.z - o.z, b.x - o.x, b.y - o.y, b.z - o.z, c.x - o.x, c.y - o.y, c.z - o.z }
end

--- The position of every vertex of a part in the car's own coordinates (+ its box), from the buffer `vb` and the map `A` of `affine`.
local function measure(part, raw, vb, A)
    local ox, oy, oz, ax, ay, az, bx, by, bz, cx, cy, cz = A[1], A[2], A[3], A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12]
    local lx, ly, lz, hx, hy, hz = 1e9, 1e9, 1e9, -1e9, -1e9, -1e9
    local xs, ys, zs = {}, {}, {}
    for k = 1, part.n do
        local px, py, pz
        if raw then local r = raw[k - 1].pos; px, py, pz = r.x, r.y, r.z else local p = vb:get(k).pos; px, py, pz = p.x, p.y, p.z end
        local x, y, z = ox + px * ax + py * bx + pz * cx, oy + px * ay + py * by + pz * cy, oz + px * az + py * bz + pz * cz
        xs[k], ys[k], zs[k] = x, y, z
        if x < lx then lx = x end
        if y < ly then ly = y end
        if z < lz then lz = z end
        if x > hx then hx = x end
        if y > hy then hy = y end
        if z > hz then hz = z end
    end
    part.x, part.y, part.z, part.lo, part.hi = xs, ys, zs, vec3(lx, ly, lz), vec3(hx, hy, hz)
end

--- The axes of the car in the space of a mesh (the inverse of the map): what a push along the car is in the mesh. m[a] = the car's axis a there; u[a] = the same of length 1.
local function axesInMesh(A)
    local a, b, c, d, e, f, g, h, i = A[4], A[7], A[10], A[5], A[8], A[11], A[6], A[9], A[12]     -- the rows of the 3x3: car = M mesh
    local det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    if math.abs(det) < 1e-12 then return nil end
    local inv = {
        { (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det },
        { (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det },
        { (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det },
    }
    local m, u = {}, {}
    for k = 1, 3 do
        local x, y, z = inv[1][k], inv[2][k], inv[3][k]
        m[k] = { x, y, z }
        local l = math.sqrt(x * x + y * y + z * z)
        u[k] = l > 1e-9 and { x / l, y / l, z / l } or { 0, 0, 0 }
    end
    return m, u
end

--- Reads one mesh of the car (under pcall by the caller: a mesh that cannot be read is left out, the others go on): the pristine vertices, the working copy, their places in the car's coordinates, and the axes of the car in the space of the mesh.
local function readPart(lab, sel, i)
    local car = ac.getCar(lab.index)
    local ref = sel:at(i)
    local vb = ref:getVertices()
    local pristine = vb and ref:getVertices()   -- every call is a fresh copy; VertexBuffer:clone() throws in this CSP
    if not pristine then lab.empty = lab.empty + 1; if #lab.emptyNames < 4 then lab.emptyNames[#lab.emptyNames + 1] = tostring(sel:name(i)) end; return end
    if not lab.fastOK then lab.fastOK = pcall(function() local r = vb.raw[0]; local x = r.pos.x + r.normal.y; assert(x == x) end) end
    local body, toCar = car.bodyTransform, car.worldToLocal
    local rootWorld = lab.root:getWorldTransformationRaw()
    local okC, chain = false, nil
    if rootWorld then okC, chain = pcall(nodeChain, ref, rootWorld) end
    local place
    if okC and chain then
        local base = followsCar(rootWorld, body) and rootWorld or body     -- the root as it is drawn, or the car's own frame when the drawing lags the physics
        place = function(x, y, z)
            local p = vec3(x, y, z)
            for k = 1, #chain do p = chain[k]:transformPoint(p) end
            return toCar:transformPoint(base:transformPoint(p))
        end
    else
        local parent = ref:getParent()
        local world = parent and parent:getWorldTransformationRaw()
        if not world then lab.noNode = lab.noNode + 1; if #lab.noNodeNames < 4 then lab.noNodeNames[#lab.noNodeNames + 1] = tostring(sel:name(i)) end; return end
        lab.chainless = lab.chainless + 1
        if not followsCar(world, body) then world = body; lab.stale = lab.stale + 1 end      -- the mesh is taken for one that sits in the space of the car
        place = function(x, y, z) return toCar:transformPoint(world:transformPoint(vec3(x, y, z))) end
    end
    local A = affine(place)
    local m, u = axesInMesh(A)
    if not m then return end
    local part = { ref = ref, vb = vb, pristine = pristine, n = vb:size(), name = sel:name(i), m = m, u = u }
    measure(part, lab.fastOK and vb.raw or nil, vb, A)
    lab.parts[#lab.parts + 1] = part
    lab.verts = lab.verts + part.n
end

--- A lab: the meshes of one car, read a few at a time (a frame has a few milliseconds for it).
local function newLab(index)
    local root = ac.findNodes("carRoot:" .. index)
    local sel = root:findMeshes("?")
    -- The pilots' cars of the pack (the Eclipse, 39 MB) came back WITHOUT their first LOD from "?" (the owner's CSP log, 2026-10-13: 178 meshes read = exactly the lower LODs B+C+D of the file,
    -- the 196 of the first one missing), so a dent was made only on the simpler LODs and never seen on a car near the camera. The first LOD is asked for by its own filter too.
    local sizes = ""
    pcall(function()
        local a = root:findMeshes("{ lod:A }")
        local parts = {}
        for _, name in ipairs({ "A", "B", "C", "D" }) do parts[#parts + 1] = name .. "=" .. #root:findMeshes("{ lod:" .. name .. " }") end
        sizes = table.concat(parts, " ")
        if #a > 0 then
            local union = sel:makeUnionWith(a)
            if #union > #sel then sel = union end
        end
    end)
    return { index = index, root = root, parts = {}, verts = 0, fastOK = false, usedAt = clock, sel = sel, nextMesh = 1, done = false, bad = 0, stale = 0, chainless = 0, ms = 0,
        total = #sel, sizes = sizes, skippedByName = 0, empty = 0, emptyNames = {}, noNode = 0, noNodeNames = {} }
end

--- The wheels in the car's own coordinates: { x, y, z, radius, half the width }, and the axle lines (z of the front pair, of the rear pair).
local function finishLab(lab)
    local car = ac.getCar(lab.index)
    local toCar = car.worldToLocal
    lab.wheels = {}
    pcall(function()
        for k = 0, 3 do
            local w = car.wheels[k]
            local p = toCar:transformPoint(w.position)
            lab.wheels[#lab.wheels + 1] = { x = p.x, y = p.y, z = p.z, r = (w.tyreRadius > 0.1 and w.tyreRadius or 0.33), hw = (w.tyreWidth > 0.05 and w.tyreWidth or 0.22) * 0.5 }
        end
    end)
    if #lab.wheels == 4 then
        table.sort(lab.wheels, function(a, b) return a.z > b.z end)
        lab.frontZ = (lab.wheels[1].z + lab.wheels[2].z) * 0.5
        lab.rearZ = (lab.wheels[3].z + lab.wheels[4].z) * 0.5
    else
        lab.wheels, lab.frontZ, lab.rearZ = {}, nil, nil
    end
    lab.sel = nil
    lab.done = true
end

--- Reads meshes until the budget of the frame is used (at least one). Returns whether the lab is done.
local function readStep(lab)
    local t0 = os.clock()
    local sel = lab.sel
    local budget = M.buildBudget or BUILD_BUDGET
    repeat
        local i = lab.nextMesh
        lab.nextMesh = i + 1
        if i <= #sel then
            if skipped(sel:name(i)) then
                lab.skippedByName = lab.skippedByName + 1
            else
                local ok, err = pcall(readPart, lab, sel, i)
                if not ok then lab.bad = lab.bad + 1; lab.firstError = lab.firstError or tostring(err) end
            end
        end
    until lab.nextMesh > #sel or lab.verts > MAX_VERTS or os.clock() - t0 >= budget
    lab.ms = lab.ms + (os.clock() - t0) * 1000
    if lab.nextMesh > #sel or lab.verts > MAX_VERTS then finishLab(lab) end
    return lab.done
end

--- How much of a dent a point of the car takes, 0..1: nothing at a wheel (and a smooth return around it), a share of it in the stiff passenger cell between the axles.
local function share(lab, x, y, z, vertical)
    local k = 1
    local wheels = lab.wheels
    for i = 1, #wheels do
        local w = wheels[i]
        if math.abs(x - w.x) < w.hw + WHEEL_SIDE then
            local dy, dz = y - w.y, z - w.z
            local r = math.sqrt(dy * dy + dz * dz) - w.r
            if r < WHEEL_CLEAR + WHEEL_FADE then
                local s = (r - WHEEL_CLEAR) / WHEEL_FADE
                if s <= 0 then return 0 end
                s = s * s * (3 - 2 * s)
                if s < k then k = s end
            end
        end
    end
    if lab.frontZ and not vertical then
        local out = math.max(z - lab.frontZ, lab.rearZ - z)      -- > 0 outside the axle lines (the crumple zones), < 0 between them
        local s = (out + 0.1) / CABIN_FADE
        s = s < 0 and 0 or (s > 1 and 1 or s)
        k = k * (CABIN_SHARE + (1 - CABIN_SHARE) * s * s * (3 - 2 * s))
    end
    return k
end

--- The most a point may move along the push (m): not across the middle line of the car, and the crumple zones do not go back past their axle line.
local function room(lab, x, z, dx, dz)
    local m = 1e9
    if dx < -0.05 and x > AXIS_KEEP then m = math.min(m, (x - AXIS_KEEP) / -dx)
    elseif dx > 0.05 and x < -AXIS_KEEP then m = math.min(m, (-AXIS_KEEP - x) / dx) end
    if lab.frontZ then
        if dz < -0.05 and z > lab.frontZ then m = math.min(m, (z - lab.frontZ) / -dz)
        elseif dz > 0.05 and z < lab.rearZ then m = math.min(m, (lab.rearZ - z) / dz) end
    end
    return m
end

--- A mesh that cannot be changed (CSP says no to it) is left as it is, once in the log; the others of the car go on.
local function markDead(lab, part, err)
    part.dead = true
    if not lab.deadWhy then
        lab.deadWhy = tostring(err)
        ac.log("[DRS Dents] " .. tostring(lab.id) .. ": the mesh " .. tostring(part.name) .. " cannot be changed (" .. lab.deadWhy .. "), it is left as it is")
    end
end

--- The point of a knock comes from the collision box of the car, not from its metal (the box of a traffic Camry is 0.6 m inside the nose; the owner, 2026-10-13: "the traffic crumples weakly"):
--- the bowl of a dent 60 cm inside the body hardly reached the bumper. The dent starts on the metal: the outermost vertex near the line of the push (at most SNAP_MAX either way).
--- A point that is off the line of every vertex (a remote car is drawn a little behind where the physics had it: a point 0.7-1 m outside the side of the Bogdan moved nothing, 2026-10-13)
--- goes to the nearest vertex within SNAP_NEAR.
local SNAP_MAX, SNAP_NEAR = 2.0, 2.5
local function surface(lab, at, dir, radius)
    local lat = math.max(0.3, radius * 0.6)
    local lat2, reach = lat * lat, SNAP_NEAR
    local best
    local nearPart, nearK, nearD2 = nil, nil, SNAP_NEAR * SNAP_NEAR
    for _, part in ipairs(lab.parts) do
        local lo, hi = part.lo, part.hi
        if not part.dead and at.x + reach >= lo.x and at.x - reach <= hi.x and at.y + reach >= lo.y and at.y - reach <= hi.y and at.z + reach >= lo.z and at.z - reach <= hi.z then
            local xs, ys, zs = part.x, part.y, part.z
            for k = 1, part.n do
                local dx, dy, dz = xs[k] - at.x, ys[k] - at.y, zs[k] - at.z
                local t = dx * dir.x + dy * dir.y + dz * dir.z
                local d2 = dx * dx + dy * dy + dz * dz
                if t > -SNAP_MAX and t < SNAP_MAX and (not best or t < best) and d2 - t * t < lat2 then best = t end
                if d2 < nearD2 then nearPart, nearK, nearD2 = part, k, d2 end
            end
        end
    end
    if not best then
        if not nearPart then return at end
        return vec3(nearPart.x[nearK], nearPart.y[nearK], nearPart.z[nearK])
    end
    return vec3(at.x + dir.x * best, at.y + dir.y * best, at.z + dir.z * best)
end

--- One dent: pushes the vertices around `at` (metres, the car's coordinates; moved onto the metal first) along `dir` (a unit vector) in a Gaussian bowl of `radius`, `depth` deep, with a slow swell; sends the changed meshes back.
local function crumple(lab, at, dir, radius, depth)
    at = surface(lab, at, dir, radius)
    local r2 = radius * radius
    local cut = r2 * 3.2                 -- 1.8 radii: the bowl is under 4 % there
    local reach = radius * 1.8
    local dx0, dy0, dz0 = dir.x, dir.y, dir.z
    local vertical = math.abs(dy0) > 0.7          -- a roof crushed from above: the stiff cell is no help
    local movedVerts, movedParts = 0, 0
    for _, part in ipairs(lab.parts) do
        local lo, hi = part.lo, part.hi
        if not part.dead and at.x + reach >= lo.x and at.x - reach <= hi.x and at.y + reach >= lo.y and at.y - reach <= hi.y and at.z + reach >= lo.z and at.z - reach <= hi.z then
            local m, u = part.m, part.u
            -- the push in this mesh's own space is the same for every vertex of it; the axes of the car in that space tilt the normals of the bowl
            local mx = dx0 * m[1][1] + dy0 * m[2][1] + dz0 * m[3][1]
            local my = dx0 * m[1][2] + dy0 * m[2][2] + dz0 * m[3][2]
            local mz = dx0 * m[1][3] + dy0 * m[2][3] + dz0 * m[3][3]
            local ml = math.sqrt(mx * mx + my * my + mz * mz)
            local ux, uy, uz = 0, 0, 0
            if ml > 1e-9 then ux, uy, uz = mx / ml, my / ml, mz / ml end
            local e1x, e1y, e1z, e2x, e2y, e2z, e3x, e3y, e3z = u[1][1], u[1][2], u[1][3], u[2][1], u[2][2], u[2][3], u[3][1], u[3][2], u[3][3]
            local xs, ys, zs, vb = part.x, part.y, part.z, part.vb
            if not part.px then                                   -- the places as they were read: what a repair puts back
                local px, py, pz = {}, {}, {}
                for k = 1, part.n do px[k], py[k], pz[k] = xs[k], ys[k], zs[k] end
                part.px, part.py, part.pz = px, py, pz
            end
            local raw = lab.fastOK and vb.raw or nil
            local any = false
            for k = 1, part.n do
                local dx, dy, dz = xs[k] - at.x, ys[k] - at.y, zs[k] - at.z
                local d2 = dx * dx + dy * dy + dz * dz
                if d2 < cut then
                    local w = math.exp(-d2 / r2)
                    local push = depth * w * (1 + ROUGH * swell(xs[k], ys[k], zs[k])) * share(lab, xs[k], ys[k], zs[k], vertical)
                    local free = room(lab, xs[k], zs[k], dx0, dz0)
                    if push > free then push = free end
                    if push > 0.0005 then
                        -- the normal follows the bowl: a surface that faces along the push (n . u < 0 for the outside of a hit) leans toward the middle of the dent, 2 push / r^2 per metre of the way from it
                        local vx, vy, vz = dx * e1x + dy * e2x + dz * e3x, dx * e1y + dy * e2y + dz * e3y, dx * e1z + dy * e2z + dz * e3z
                        local lean = 2 * push / r2
                        xs[k], ys[k], zs[k] = xs[k] + dx0 * push, ys[k] + dy0 * push, zs[k] + dz0 * push
                        if raw then
                            local r = raw[k - 1]
                            local pos, nor = r.pos, r.normal
                            pos.x, pos.y, pos.z = pos.x + mx * push, pos.y + my * push, pos.z + mz * push
                            local c = lean * (nor.x * ux + nor.y * uy + nor.z * uz)
                            local ax, ay, az = nor.x + c * vx, nor.y + c * vy, nor.z + c * vz
                            local l = math.sqrt(ax * ax + ay * ay + az * az)
                            if l > 1e-6 then nor.x, nor.y, nor.z = ax / l, ay / l, az / l end
                        else
                            local v = vb:get(k)
                            local pos, nor = v.pos, v.normal
                            local c = lean * (nor.x * ux + nor.y * uy + nor.z * uz)
                            local ax, ay, az = nor.x + c * vx, nor.y + c * vy, nor.z + c * vz
                            local l = math.sqrt(ax * ax + ay * ay + az * az)
                            local normal = l > 1e-6 and vec3(ax / l, ay / l, az / l) or nor
                            vb:set(k, ac.MeshVertex.new(vec3(pos.x + mx * push, pos.y + my * push, pos.z + mz * push), normal, v.uv))
                        end
                        any = true
                        movedVerts = movedVerts + 1
                    end
                end
            end
            if any then
                movedParts = movedParts + 1
                local okA, errA = pcall(part.ref.alterVertices, part.ref, vb)
                if not okA then markDead(lab, part, errA) end
            end
        end
    end
    return movedVerts, movedParts
end

--- Puts every mesh of the car back as it was read: the pristine vertices go in, and fresh copies are taken (the buffer that was sent may be taken over by the engine).
local function restore(lab)
    if not lab.done then return end
    for _, part in ipairs(lab.parts) do
        if not part.dead then
            local ok, err = pcall(function()
                part.ref:alterVertices(part.pristine)
                part.pristine = part.ref:getVertices()
                part.vb = part.ref:getVertices()
                if part.px then
                    local xs, ys, zs, px, py, pz = part.x, part.y, part.z, part.px, part.py, part.pz
                    for k = 1, part.n do xs[k], ys[k], zs[k] = px[k], py[k], pz[k] end
                end
            end)
            if not ok then markDead(lab, part, err) end
        end
    end
end

local TELL_DENTS, told = 40, 0
local detailSaid = false
local function applyDent(lab, d)
    local len = math.sqrt(d.dx * d.dx + d.dy * d.dy + d.dz * d.dz)
    if len < 1 then return end
    local verts, parts = crumple(lab, vec3(d.x / 100, d.y / 100, d.z / 100), vec3(d.dx / len, d.dy / len, d.dz / len), d.radius / 100, d.depth / 100)
    if told < TELL_DENTS then          -- the first dents of a session in the CSP log: a dent the server made but nobody sees shows here as "0 vertices"
        told = told + 1
        local okL, lod = pcall(function() return ac.getCar(lab.index).activeLOD end)
        ac.log(string.format("[DRS Dents] %s: a dent of %d cm at %d,%d,%d moved %d vertices in %d of %d meshes (LOD %s on screen)", tostring(lab.id), d.depth, d.x, d.y, d.z, verts, parts, #lab.parts, okL and tostring(lod) or "?"))
    end
end

local function fail(err)
    broken = true
    brokenWhy = tostring(err)
    ac.log("[DRS Dents] the meshes cannot be changed, the dents are off: " .. brokenWhy)
end

local function indexOfSlot(slot)
    local sim = ac.getSim()
    for i = 0, sim.carsCount - 1 do
        local car = ac.getCar(i)
        if car and car.isConnected and car.sessionID == slot then return i, car end
    end
    return nil
end

-- ---------------------------------------------------------------- what the server tells
local function restoreSlot(slot)
    local i = indexOfSlot(slot)
    local lab = i and labs[i]
    if lab and lab.done then
        local ok, err = pcall(restore, lab)
        if not ok then fail(err) end
    end
end

local function mySlot()
    local me = ac.getCar(0)
    return me and me.sessionID
end

local function onFrame(body)
    local slot, epoch = body:match("^DENT:RESET:(%d+):(%d+)$")
    if slot then
        slot, epoch = tonumber(slot), tonumber(epoch)
        local c = cars[slot]
        if c and c.applied > 0 and not broken then restoreSlot(slot) end
        if c and #c.dents > 0 and slot == mySlot() then pcall(ac.setSystemMessage, "DRS", T(K("dents.repaired"))) end
        cars[slot] = { epoch = epoch, dents = {}, applied = 0 }
        return
    end
    local f = { body:match("^DENT:(%d+):(%d+):(%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%d+):(%d+)$") }
    if #f ~= 11 then return end
    for i = 1, 11 do f[i] = tonumber(f[i]) end
    local slot, epoch, id = f[1], f[2], f[3]
    if slot > 255 then return end
    local c = cars[slot]
    if not c or c.epoch ~= epoch then
        if c and c.applied > 0 and not broken then restoreSlot(slot) end
        c = { epoch = epoch, dents = {}, applied = 0 }
        cars[slot] = c
    end
    for _, d in ipairs(c.dents) do if d.id == id then return end end
    if #c.dents >= 16 then return end
    c.dents[#c.dents + 1] = { id = id, x = f[4], y = f[5], z = f[6], dx = f[7], dy = f[8], dz = f[9], depth = f[10], radius = f[11] }
end

DRS_Net.onMessage(function(msg)
    local body = msg:match("^§DRS:(.*)$")
    if body and body:sub(1, 5) == "DENT:" then onFrame(body) end
end)

-- ---------------------------------------------------------------- the pending dents, car by car
--- Is the car within RANGE_M of the camera? Worked out from the positions, not from car.distanceToCamera: the owner (2026-10-13) saw the dents of the cars around from a third-person view and none
--- from the cockpit, and that field is the one thing in the way of a dent that a camera mode could change.
local function nearCamera(car, camera)
    if not camera then return true end
    local ok, d = pcall(function() return car.position:distance(camera) end)
    return not ok or d < RANGE_M
end

--- A lab that has been read to the end: usable, or the car is marked as one that cannot be crumpled. Says once for a model what was read of it.
local function readDone(i, lab)
    local id = lab.id
    if #lab.parts == 0 then
        unreadable[i] = id
        labs[i] = nil
        ac.log("[DRS Dents] the car " .. tostring(id) .. " cannot be crumpled (no mesh could be read" .. (lab.firstError and (": " .. lab.firstError) or "") .. ")")
        return false
    end
    if not logged[id] then
        logged[id] = true
        local lods = 0
        for _, part in ipairs(lab.parts) do if tostring(part.name or ""):lower():find("lod", 1, true) then lods = lods + 1 end end
        ac.log(string.format("[DRS Dents] %s: of %d meshes of the car (%s) %d skipped by name, %d without vertices%s, %d without a node%s; %d read", tostring(id), lab.total,
            lab.sizes ~= "" and ("LODs " .. lab.sizes) or "no LOD filter", lab.skippedByName, lab.empty, lab.empty > 0 and (" (" .. table.concat(lab.emptyNames, ", ") .. ")") or "",
            lab.noNode, lab.noNode > 0 and (" (" .. table.concat(lab.noNodeNames, ", ") .. ")") or "", #lab.parts))
        ac.log(string.format("[DRS Dents] %s: %d meshes (%d named like a LOD), %d vertices, %d wheels, read in %.0f ms%s%s%s", tostring(id), #lab.parts, lods, lab.verts, #lab.wheels, lab.ms,
            lab.chainless > 0 and string.format(", %d placed by their world matrix (no chain of nodes to the car)", lab.chainless) or "",
            lab.stale > 0 and string.format(", %d with a transform that did not follow the car", lab.stale) or "",
            lab.bad > 0 and string.format(", %d could not be read (%s)", lab.bad, tostring(lab.firstError)) or ""))
    end
    return true
end

--- The dents are made on every LOD of a car, but the owner saw them only on the detailed one (from the cockpit: dented; from outside, where the game shows a simpler LOD sooner: not, 2026-10-13).
--- So a dented car near the camera is drawn with its detailed LOD (CSP keeps it for a few frames: asked every frame), the nearest DETAIL_CARS within DETAIL_M.
local DETAIL_M, DETAIL_CARS = 90, 12
local function holdDetail()
    if not ac.forceDetailedCarLOD then return end   -- csp:optional (a CSP without it: the game picks the LOD)
    local camera = ac.getCameraPosition()
    local sim = ac.getSim()
    local list = {}
    for i = 0, sim.carsCount - 1 do
        local car = ac.getCar(i)
        local c = car and car.isConnected and cars[car.sessionID]
        if c and c.applied > 0 then
            local d = car.position:distance(camera)
            if d < DETAIL_M then list[#list + 1] = { i = i, d = d } end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    for k = 1, math.min(#list, DETAIL_CARS) do ac.forceDetailedCarLOD(list[k].i) end   -- csp:optional
end

--- The labs that are being read go on a few milliseconds a frame.
local function advanceBuilds()
    for i, lab in pairs(labs) do
        if not lab.done then
            local ok, err = pcall(readStep, lab)
            if not ok then
                unreadable[i] = lab.id; labs[i] = nil
                ac.log("[DRS Dents] the car " .. tostring(lab.id) .. " could not be read: " .. tostring(err))
            elseif lab.done and not lab.checked then
                lab.checked = true
                readDone(i, lab)
            end
        end
    end
end

local function process()
    local sim = ac.getSim()
    local camera
    if ac.getCameraPosition then local ok, p = pcall(ac.getCameraPosition); if ok then camera = p end end
    local made = 0
    local present = {}
    for i = 0, sim.carsCount - 1 do
        local car = ac.getCar(i)
        if car and car.isConnected then present[car.sessionID] = i end
    end
    for slot, c in pairs(cars) do
        local i = present[slot]
        if i and c.applied < #c.dents and made < PER_PASS then
            local car = ac.getCar(i)
            local id, driver = ac.getCarID(i), tostring(ac.getDriverName(i) or "")
            local lab = labs[i]
            if lab and (lab.id ~= id or lab.driver ~= driver) then labs[i] = nil; lab = nil; c.applied = 0 end   -- another car in this place: its meshes are new
            if unreadable[i] and unreadable[i] ~= id then unreadable[i] = nil end
            if i == 0 or nearCamera(car, camera) then
                if not lab and not unreadable[i] then
                    local okL, made2 = pcall(newLab, i)
                    if okL then lab = made2; lab.id, lab.driver = id, driver; labs[i] = lab
                    else unreadable[i] = id; ac.log("[DRS Dents] the car " .. tostring(id) .. " could not be read: " .. tostring(made2)) end
                end
                if not lab then c.applied = #c.dents end              -- this one cannot be read: nothing to crumple, not tried again
                if lab and not lab.done then
                    local okR, errR = pcall(readStep, lab)
                    if not okR then
                        unreadable[i] = id; labs[i] = nil; lab = nil; c.applied = #c.dents
                        ac.log("[DRS Dents] the car " .. tostring(id) .. " could not be read: " .. tostring(errR))
                    end
                end
                if lab and lab.done and not lab.checked then
                    lab.checked = true
                    if not readDone(i, lab) then lab = nil; c.applied = #c.dents end
                end
                if lab and lab.done then
                    lab.usedAt = clock
                    while c.applied < #c.dents and made < PER_PASS do
                        c.applied = c.applied + 1
                        applyDent(lab, c.dents[c.applied])
                        made = made + 1
                    end
                end
            end
        end
    end
    -- the meshes of a car with nothing applied are let go after a while (one with dents keeps its pristine copy: it is what a repair puts back)
    for i, lab in pairs(labs) do
        if clock - lab.usedAt > KEEP_SECONDS then
            local keep = false
            for slot, c in pairs(cars) do if present[slot] == i and c.applied > 0 then keep = true end end
            if not keep then labs[i] = nil end
        end
    end
end

-- ---------------------------------------------------------------- the own car: knocks and repairs
local function remember()
    local me = ac.getCar(0)
    if not me then return end
    local v = me.velocity
    hist[#hist + 1] = { t = clock, x = v.x, y = v.y, z = v.z }
    if #hist > HISTORY then table.remove(hist, 1) end
end

--- The own velocity from about `age` seconds ago (the oldest frame that is not younger, or the oldest there is).
local function velocityBefore(age)
    for i = #hist, 1, -1 do
        if clock - hist[i].t >= age then return hist[i] end
    end
    return hist[1]
end

local function unit(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-6 then return 0, 0, 0 end
    return x / l, y / l, z / l
end

--- The way the metal is pushed on a car: mostly the way the other car came, a little towards the middle of the car (so a dent is always IN).
local function pushOn(car, hit, dx, dy, dz)
    local center = car.aabbCenter
    local ix, iz = 0, 0
    if type(center) ~= "number" then ix, iz = unit(center.x - hit.x, 0, center.z - hit.z) end
    local x, y, z = unit(dx * 0.7 + ix * 0.3, math.max(-0.35, math.min(0.35, dy * 0.7)), dz * 0.7 + iz * 0.3)
    if x == 0 and y == 0 and z == 0 then x, z = ix, iz end
    return x, y, z
end

local function cm(v) local r = math.floor(math.abs(v) * 100 + 0.5); return v < 0 and -r or r end

--- The car whose box holds the point (a little bigger), the nearest one; nil = the track.
local function carAt(hitWorld, me, slack)
    local sim = ac.getSim()
    local best, bestIndex, bestCar = slack or BOX_SLACK, nil, nil
    for i = 1, sim.carsCount - 1 do
        local car = ac.getCar(i)
        if car and car.isConnected and car.position:distance(me.position) < 14 then
            local size, center = car.aabbSize, car.aabbCenter
            if type(size) ~= "number" and type(center) ~= "number" then
                local p = car.worldToLocal:transformPoint(hitWorld)
                local ox = math.max(0, math.abs(p.x - center.x) - size.x * 0.5)
                local oy = math.max(0, math.abs(p.y - center.y) - size.y * 0.5)
                local oz = math.max(0, math.abs(p.z - center.z) - size.z * 0.5)
                local over = math.sqrt(ox * ox + oy * oy + oz * oz)
                if over < best then best, bestIndex, bestCar = over, i, car end
            end
        end
    end
    return bestIndex, bestCar
end

--- Tells the server about a knock of the own car. `given` = the point of it in the world when DRS_Solid found it (a car that went into another one without the game's contact), else the game's collisionPosition.
local function report(given, givenIndex)
    local me = ac.getCar(0)
    local before = velocityBefore(BEFORE_SECONDS)
    if not me or not before then return end
    local hitMine, hitWorld
    if given then
        hitWorld = given
        hitMine = me.worldToLocal:transformPoint(given)
    else
        hitMine = me.collisionPosition
        hitWorld = me.bodyTransform:transformPoint(hitMine)
    end
    local otherIndex, other
    if givenIndex then
        otherIndex, other = givenIndex, ac.getCar(givenIndex)
    else
        local isCar = false
        pcall(function() isCar = (me.collidedWith or 0) ~= 0 end)       -- the game itself says it was a car and not the track
        otherIndex, other = carAt(hitWorld, me, isCar and WIDE_SLACK or BOX_SLACK)
    end
    local key = other and other.sessionID or -1
    if clock - (lastFor[key] or -100) < REPORT_GAP then return end      -- the same car was told a moment ago
    local rx, ry, rz = before.x, before.y, before.z
    if other then
        local vo = other.velocity
        rx, ry, rz = rx - vo.x, ry - vo.y, rz - vo.z
    end
    local kmh = math.floor(math.sqrt(rx * rx + ry * ry + rz * rz) * 3.6 + 0.5)
    if kmh < (other and MIN_KMH or WALL_KMH) then return end
    local ux, uy, uz = unit(rx, ry, rz)                    -- the way my car moves relative to the other one
    -- on my car: the other one pushes the opposite way
    local mw = me.worldToLocal:transformVector(vec3(-ux, -uy, -uz))
    local mdx, mdy, mdz = pushOn(me, hitMine, mw.x, mw.y, mw.z)
    local text
    if other then
        local lp = other.worldToLocal:transformPoint(hitWorld)
        local lw = other.worldToLocal:transformVector(vec3(ux, uy, uz))
        local odx, ody, odz = pushOn(other, lp, lw.x, lw.y, lw.z)
        text = string.format("HIT:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d", other.sessionID, kmh, cm(lp.x), cm(lp.y), cm(lp.z), cm(odx), cm(ody), cm(odz),
            cm(hitMine.x), cm(hitMine.y), cm(hitMine.z), cm(mdx), cm(mdy), cm(mdz))
    else
        text = string.format("HIT:-:%d:0:0:0:0:0:0:%d:%d:%d:%d:%d:%d", kmh, cm(hitMine.x), cm(hitMine.y), cm(hitMine.z), cm(mdx), cm(mdy), cm(mdz))
    end
    lastReport = clock
    lastFor[key] = clock
    DRS_Net.send("dent", text)
end

--- Called every frame: a knock starts when collisionDepth rises from nothing (polled, not ac.onCarCollision: a CSP 0.2.4 has the fields but not that callback).
local function watchKnocks(dt)
    local me = ac.getCar(0)
    if not me then return end
    local inKnock = me.collisionDepth > 0
    if inKnock and not wasIn and clock - lastReport >= REPORT_MIN then
        local ok, err = pcall(report)
        if not ok then ac.log("[DRS Dents] a knock could not be told: " .. tostring(err)) end
    end
    wasIn = inKnock
    -- the pits: standing there for a few seconds makes the car new (the server only checks that it stands)
    local standing = me.speedKmh < 5
    if standing and (me.isInPit or me.isInPitlane) then pitFor = pitFor + dt else pitFor = 0 end
    local mine = cars[me.sessionID]
    if pitFor >= PIT_SECONDS and mine and #mine.dents > 0 and clock - lastRepair >= REPAIR_GAP then
        lastRepair = clock
        DRS_Net.send("dent", "REPAIR")
    end
end

function M.update(dt)
    clock = clock + dt
    local ok, err = pcall(remember)
    if not ok and not broken then ac.log("[DRS Dents] " .. tostring(err)) end
    ok, err = pcall(watchKnocks, dt)
    if not ok then ac.log("[DRS Dents] " .. tostring(err)) end
    if broken then return end
    ok, err = pcall(advanceBuilds)
    if not ok then ac.log("[DRS Dents] " .. tostring(err)) end
    ok, err = pcall(holdDetail)
    if not ok and not detailSaid then detailSaid = true; ac.log("[DRS Dents] the detailed LOD cannot be held: " .. tostring(err)) end
    if clock < passAt then return end
    passAt = clock + PASS_SECONDS
    ok, err = pcall(process)
    if not ok then fail(err) end
end

--- A knock that DRS_Solid found: the point in the world. Told like a knock of the game's own (the same rules: a pause between two, a minimum speed).
function M.knock(point, carIndex)
    if broken or clock - lastReport < REPORT_MIN then return end
    local ok, err = pcall(report, point, carIndex)
    if not ok then ac.log("[DRS Dents] a knock could not be told: " .. tostring(err)) end
end

--- For the tests and the help: the dents of every slot, and how many are applied.
function M.cars() return cars end
function M.isBroken() return broken, brokenWhy end
function M.labCount() local n = 0; for _ in pairs(labs) do n = n + 1 end; return n end

-- Chat command "!repair" makes his own car new (it must stand). Local only. There is no command to switch the dents off.
if ac.onChatMessage then
    ac.onChatMessage(function(msg, sender)
        if type(sender) == "number" and sender ~= 0 then return false end
        if type(msg) ~= "string" then return end
        local text = msg:lower():match("^%s*(!%a+)%s*$")
        if text ~= "!repair" then return end
        local me = ac.getCar(0)
        if me and me.speedKmh >= 5 then pcall(ac.setSystemMessage, "DRS", T("dents.repair_move")) return true end
        DRS_Net.send("dent", "REPAIR")
        return true
    end)
end

_G.DRS_Dents = M
return M
end)()

-- ---------------------------------------------------------------- the frame
local sim = ac.getSim()
local clock, session, said = 0, nil, false

function script.update(dt)
  clock = clock + dt
  if not said then
    said = true
    ac.log('[DRS Dents] ' .. VERSION .. ' loaded, online events ' .. (accessEvent and 'on' or 'OFF'))
  end
  local s = sim.currentSessionIndex
  if session ~= nil and s ~= session and #mine.dents > 0 then repair() end   -- a new session: every car starts whole
  session = s
  DRS_Dents.update(dt)
  local ok, err = pcall(flush, clock)
  if not ok then ac.log('[DRS Dents] ' .. tostring(err)) end
end
