
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
