-- node tests/run.js tests/dents_test.lua : the built dents.lua in a fake CSP (fengari, Lua 5.3). Run `node build.js` first.
-- What it checks: the own knocks become the DRS Street dents of a pilot's car, the list goes out in one event (rate limited, repeated for joiners),
-- the events of the others land on THEIR slot only, repair / a new session start a new epoch, the caps hold, the depth knob works.
local fails = 0
local function check(cond, what) if not cond then fails = fails + 1; print('FAIL: ' .. what) end end

local function setup(cfgOverride)
  local me = { sessionID = 2, isConnected = true, velocity = { x = 0, y = 0, z = 0 }, collisionDepth = 0, speedKmh = 0, isInPit = false, isInPitlane = false }
  local other = { sessionID = 5, isConnected = true, velocity = { x = 0, y = 0, z = 0 } }
  local W = { sent = {}, cb = nil, me = me, sim = { carsCount = 2, currentSessionIndex = 0 } }
  local function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, { __index = { distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end } }) end
  local item = function() return {} end
  _G.vec3 = vec3
  _G.script = {}
  _G.ac = {
    log = function() end,
    setSystemMessage = function(_, text) W.message = text end,
    configValues = function(d) return cfgOverride or d end,
    getSim = function() return W.sim end,
    getCar = function(i) return i == 0 and me or (i == 1 and other or nil) end,
    getCarID = function(i) return 'an_nextgen_chevy' end,
    getDriverName = function(i) return 'pilot' .. i end,
    StructItem = { key = item, int32 = item, uint8 = item, int16 = item, int8 = item, array = item },
    OnlineEvent = function(layout, cb)
      W.cb = cb
      local buf = {}
      for _, k in ipairs({ 'x', 'y', 'z', 'dx', 'dy', 'dz', 'depth', 'radius' }) do buf[k] = {} end
      local send = function(msg, again)
        local copy = { epoch = buf.epoch, n = buf.n, again = again }
        for _, k in ipairs({ 'x', 'y', 'z', 'dx', 'dy', 'dz', 'depth', 'radius' }) do copy[k] = {}; for i = 0, 11 do copy[k][i] = buf[k][i] end end
        W.sent[#W.sent + 1] = copy
        cb({ sessionID = me.sessionID, index = 0 }, copy)   -- CSP echoes the own message
        return true
      end
      return send, function() return buf end
    end,
  }
  _G.DRS_Dents, _G.DRS_Net, _G.DRS_I18N = nil, nil, nil
  local chunk = assert(load(assert(readfile(ROOT .. '/dents.lua'), 'dents.lua is not built'), '=dents.lua'))
  chunk()
  return W
end

local W = setup()
local function last() return W.sent[#W.sent] end
local function mine() return DRS_Dents.cars()[2] end

script.update(0.016)
check(#W.sent == 1 and last().n == 0 and last().again == true, 'the first frame tells the empty list, repeated for joiners')
check(mine() and #mine().dents == 0, 'the own car is known with no dents')
local epoch0 = last().epoch

-- a wall at 60 km/h: the DRS Street pilot dent (9 cm deep, 53 cm wide) at the own point and way
DRS_Net.send('dent', 'HIT:-:60:0:0:0:0:0:0:10:50:200:0:0:-100')
script.update(0.4)
check(#W.sent == 2 and last().n == 1, 'a wall knock is sent')
check(last().depth[0] == 9 and last().radius[0] == 53 and last().z[0] == 200 and last().dz[0] == -100, 'the wall dent has the pilot size: ' .. tostring(last().depth[0]) .. '/' .. tostring(last().radius[0]))
check(#mine().dents == 1 and mine().dents[1].depth == 9, 'the own car got the dent here at once')

-- a car at 100 km/h right after: held back by the rate limit, then sent
DRS_Net.send('dent', 'HIT:5:100:0:0:0:0:0:0:0:50:-200:0:0:100')
script.update(0.1)
check(#W.sent == 2, 'no second message within 0.3 s')
script.update(0.25)
check(#W.sent == 3 and last().n == 2 and last().depth[1] == 26 and last().radius[1] == 66, 'the car knock at 100 km/h is 26/66')
check(last().epoch == epoch0, 'the same life of the car')

-- too slow: nothing
DRS_Net.send('dent', 'HIT:5:10:0:0:0:0:0:0:0:50:-200:0:0:100')
DRS_Net.send('dent', 'HIT:-:30:0:0:0:0:0:0:0:50:-200:0:0:100')
script.update(0.5)
check(#W.sent == 3, 'a car under 14 km/h and a wall under 35 leave nothing')
-- garbage: nothing, no error
DRS_Net.send('dent', 'HIT:5:100:0:0:0')
DRS_Net.send('dent', 'HIT:5:100:0:0:0:0:0:0:0:50:-900:0:0:100')
script.update(0.5)
check(#W.sent == 3, 'a broken report and a point outside the car are ignored')

-- another pilot's event lands on HIS slot (from the sender), whatever it says
local function remote(slot, epoch, list)
  local d = { epoch = epoch, n = #list }
  for _, k in ipairs({ 'x', 'y', 'z', 'dx', 'dy', 'dz', 'depth', 'radius' }) do d[k] = {}; for i = 0, 11 do d[k][i] = list[i + 1] and list[i + 1][k] or 0 end end
  W.cb({ sessionID = slot, index = 1 }, d)
end
remote(5, 77, { { x = 0, y = 40, z = 210, dx = 0, dy = 0, dz = -100, depth = 20, radius = 60 } })
local his = DRS_Dents.cars()[5]
check(his and his.epoch == 77 and #his.dents == 1 and his.dents[1].depth == 20, 'the dent of the other pilot is on his car')
check(#mine().dents == 2, 'my car is untouched by his event')
remote(5, 77, { { x = 0, y = 40, z = 210, dx = 0, dy = 0, dz = -100, depth = 20, radius = 60 } })
check(#DRS_Dents.cars()[5].dents == 1, 'the same list again adds nothing')
remote(5, 78, {})
check(DRS_Dents.cars()[5].epoch == 78 and #DRS_Dents.cars()[5].dents == 0, 'his repair (new epoch, empty) clears his car')
W.cb(nil, { epoch = 5, n = 1 })
check(DRS_Dents.cars()[5].epoch == 78, 'a message without a sender is ignored')

-- repair: a new epoch, empty
DRS_Net.send('dent', 'REPAIR')
script.update(0.5)
check(last().n == 0 and last().epoch ~= epoch0 and #mine().dents == 0, 'the repair tells a new empty life')
check(W.message == 'Кузов відремонтовано.', 'the pilot is told: ' .. tostring(W.message))

-- caps: 12 dents a car, 110 cm on one spot
for i = 1, 14 do DRS_Net.send('dent', string.format('HIT:5:60:0:0:0:0:0:0:%d:50:%d:0:0:-100', (i % 2) * 100 - 50, i * 80 - 600)) end
script.update(0.5)
check(last().n == 12, '12 dents at most: ' .. tostring(last().n))
DRS_Net.send('dent', 'REPAIR')
script.update(0.5)
for _ = 1, 6 do DRS_Net.send('dent', 'HIT:5:400:0:0:0:0:0:0:0:50:300:0:0:-100') end
script.update(0.5)
local sum = 0
for i = 0, last().n - 1 do sum = sum + last().depth[i] end
check(last().n == 3 and sum == 110, 'one spot takes 110 cm at most: ' .. last().n .. ' dents, ' .. sum .. ' cm')

-- a new session: whole again
local before = last().epoch
W.sim.currentSessionIndex = 1
script.update(0.5)
check(last().n == 0 and last().epoch ~= before, 'a new session repairs the car')

-- the depth knob
W = setup({ depth = 0.5, minKmh = 14 })
script.update(0.4)
DRS_Net.send('dent', 'HIT:-:60:0:0:0:0:0:0:10:50:200:0:0:-100')
script.update(0.4)
check(W.sent[#W.sent].depth[1 - 1] == 5, 'depth = 0.5 halves the dent: ' .. tostring(W.sent[#W.sent].depth[0]))

if fails > 0 then print(fails .. ' failed'); error('tests failed') end
print('dents_test: all passed')
