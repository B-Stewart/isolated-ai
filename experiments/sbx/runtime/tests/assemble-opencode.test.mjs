import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const runtime = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const assembler = path.join(runtime, 'assemble-opencode.mjs');

async function fixture(t, base, fragments = {}) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'isoai-opencode-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const fragmentsDir = path.join(root, 'fragments');
  const home = path.join(root, 'guest-home');
  await mkdir(fragmentsDir);
  await writeFile(path.join(root, 'base.json'), JSON.stringify(base));
  for (const [name, fragment] of Object.entries(fragments))
    await writeFile(path.join(fragmentsDir, name), JSON.stringify(fragment));
  return { root, fragmentsDir, home, env: { ...process.env, HOME: home,
    ISOAI_OPENCODE_BASE: path.join(root, 'base.json'), ISOAI_OPENCODE_FRAGMENTS: fragmentsDir } };
}

function run(env) {
  const result = spawnSync(process.execPath, [assembler], { env, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(result.stderr);
}

test('base-only config remains agent-neutral and is written under guest HOME', async t => {
  const f = await fixture(t, { update: 'disable', plugins: [], skills: [], mcp: { servers: {} } });
  run(f.env);
  const output = path.join(f.home, '.config/opencode/opencode.json');
  const config = JSON.parse(await readFile(output, 'utf8'));
  assert.deepEqual(config, { update: 'disable', plugins: [], skills: [], mcp: { servers: {} } });
  assert.equal('oh-my-opencode-slim' in config, false);
});

test('sorted fragments merge unique plugins and skills with disjoint MCP servers', async t => {
  const f = await fixture(t, { plugins: ['base'], skills: ['/base'], mcp: { servers: {} } }, {
    '20.json': { plugins: ['shared', 'later'], skills: ['/later'], mcp: { servers: { zed: { type: 'local' } } } },
    '10.json': { plugins: ['shared', 'first'], skills: ['/base', '/first'], mcp: { servers: { alpha: { type: 'remote' } } } },
  });
  run(f.env);
  const output = path.join(f.home, '.config/opencode/opencode.json');
  const config = JSON.parse(await readFile(output, 'utf8'));
  assert.deepEqual(config.plugins, ['base', 'shared', 'first', 'later']);
  assert.deepEqual(config.skills, ['/base', '/first', '/later']);
  assert.deepEqual(Object.keys(config.mcp.servers), ['alpha', 'zed']);
  const firstRun = await readFile(output, 'utf8');
  run(f.env);
  assert.equal(await readFile(output, 'utf8'), firstRun);
});

test('conflicting MCP server definitions fail instead of overwriting', async t => {
  const f = await fixture(t, { mcp: { servers: { same: { command: 'a' } } } }, {
    'fragment.json': { mcp: { servers: { same: { command: 'b' } } } },
  });
  const result = spawnSync(process.execPath, [assembler], { env: f.env, encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /conflicting MCP server 'same'/);
});
