// node build.js [ref]  -> dents.lua = src/head.lua + DRS_Dents.lua of DRS Street at <ref> (default origin/main) + src/tail.lua
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const repo = path.resolve(__dirname, '..', 'DRS_Street');
const ref = process.argv[2] || 'origin/main';
const git = (...args) => execFileSync('git', ['-C', repo, ...args], { encoding: 'utf8' });
const commit = git('rev-parse', '--short', ref).trim();
const mod = git('show', `${ref}:client/lua/DRS_Dents.lua`).replace(/\r\n/g, '\n');
const part = (f) => fs.readFileSync(path.join(__dirname, 'src', f), 'utf8').replace(/\r\n/g, '\n');

const out = [
  part('head.lua'),
  `-- ================================================================ DRS_Dents.lua of DRS Street ${commit} (do not edit here)`,
  ';(function()',
  mod.trimEnd(),
  'end)()',
  part('tail.lua'),
].join('\n');
fs.writeFileSync(path.join(__dirname, 'dents.lua'), out);
console.log(`dents.lua: DRS_Dents.lua of ${commit}, ${out.length} bytes`);
