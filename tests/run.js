// usage (from the project root): node tests/run.js tests/engine_test.lua
// Runs a Lua file under fengari (Lua 5.3, same language version as the BeamMP server's 5.3.5).
const path = require('path');
const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const root = path.resolve(__dirname, '..').replace(/\\/g, '/');
lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring('ROOT'));
lua.lua_pushstring(L, to_luastring(process.argv[3] || ''));
lua.lua_setglobal(L, to_luastring('ARG1')); // optional flag, e.g. "trace"
// readfile(path) -> text or nil (fengari has no io.open)
lua.lua_pushjsfunction(L, function (L) {
  try { lua.lua_pushstring(L, to_luastring(fs.readFileSync(lua.lua_tojsstring(L, 1), 'utf8'))); } catch (e) { lua.lua_pushnil(L); }
  return 1;
});
lua.lua_setglobal(L, to_luastring('readfile'));
if (lauxlib.luaL_dofile(L, to_luastring(process.argv[2])) !== lua.LUA_OK) {
  console.error(lua.lua_tojsstring(L, -1));
  process.exit(1);
}
