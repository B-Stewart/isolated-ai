#!/opt/isoai/tooling/node/bin/node
import { readdir, readFile, mkdir, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

const basePath = process.env.ISOAI_OPENCODE_BASE ?? '/opt/isoai/opencode/base.json';
const fragmentsPath = process.env.ISOAI_OPENCODE_FRAGMENTS ?? '/opt/isoai/opencode/fragments.d';
const home = process.env.HOME ?? os.homedir();
const outputPath = path.join(home, '.config/opencode/opencode.json');

function merge(target, fragment, source) {
  for (const [key, value] of Object.entries(fragment)) {
    if (key === 'plugins' || key === 'skills') {
      if (!Array.isArray(value)) throw new Error(`${source}: ${key} must be an array`);
      target[key] = [...new Set([...(target[key] ?? []), ...value])];
    } else if (key === 'mcp' && value && typeof value === 'object' && !Array.isArray(value)) {
      target.mcp ??= {};
      target.mcp.servers ??= {};
      for (const [name, config] of Object.entries(value.servers ?? {})) {
        if (name in target.mcp.servers && JSON.stringify(target.mcp.servers[name]) !== JSON.stringify(config))
          throw new Error(`${source}: conflicting MCP server '${name}'`);
        target.mcp.servers[name] = config;
      }
      for (const [other, config] of Object.entries(value)) {
        if (other === 'servers') continue;
        assign(target.mcp, other, config, source);
      }
    } else assign(target, key, value, source);
  }
}

function assign(target, key, value, source) {
  if (key in target && JSON.stringify(target[key]) !== JSON.stringify(value))
    throw new Error(`${source}: conflicting config key '${key}'`);
  target[key] = value;
}

const config = JSON.parse(await readFile(basePath, 'utf8'));
for (const file of (await readdir(fragmentsPath)).filter(name => name.endsWith('.json')).sort()) {
  merge(config, JSON.parse(await readFile(path.join(fragmentsPath, file), 'utf8')), file);
}

const directory = path.dirname(outputPath);
await mkdir(directory, { recursive: true });
const temporary = `${outputPath}.${process.pid}.tmp`;
await writeFile(temporary, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
await rename(temporary, outputPath);
