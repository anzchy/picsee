import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, existsSync } from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const scratch = path.join(process.env.HOME, '.picsee/herdr/gpt-imple-1/test-runs');
mkdirSync(scratch, { recursive: true });
const lock = path.join(root, 'scripts/heavy-lock.sh');
function environment() {
  const home = mkdtempSync(path.join(scratch, 'lock-'));
  return { ...process.env, HOME: home, PICSEE_HEAVY_LOCK_WAIT_SECS: '1', MDPRO_HEAVY_LOCK_WAIT_SECS: '1', PICSEE_HEAVY_LOCK_HELD: '', MDPRO_HEAVY_LOCK_HELD: '' };
}
function run(args, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(lock, args, { env, cwd: root });
    let output = '';
    child.stdout.on('data', b => output += b);
    child.stderr.on('data', b => output += b);
    child.on('error', reject);
    child.on('close', (code, signal) => resolve({ code, signal, output }));
  });
}
test('uses picsee machine-wide default and exports nesting flag', () => {
  const env = environment();
  const r = spawnSync(lock, ['bash', '-c', 'test "$PICSEE_HEAVY_LOCK_HELD" = 1 && test -f "$HOME/.picsee/locks/heavy.lock/owner"'], { env });
  assert.equal(r.status, 0, r.stderr.toString());
});
test('two independent invocations serialize command lifetimes', async () => {
  const env = environment();
  const events = path.join(env.HOME, 'events');
  const cmd = ['bash', '-c', 'echo start >> "$1"; sleep 0.3; echo end >> "$1"', '_', events];
  const results = await Promise.all([run(cmd, env), run(cmd, env)]);
  assert.deepEqual(results.map(r => r.code), [0, 0]);
  assert.equal(readFileSync(events, 'utf8'), 'start\nend\nstart\nend\n');
});
test('nested use shares held flag without deadlock', () => {
  const env = environment();
  const r = spawnSync(lock, ['bash', '-c', 'test "$PICSEE_HEAVY_LOCK_HELD" = 1 && "$1" true', '_', lock], { env, timeout: 5000 });
  assert.equal(r.status, 0, r.stderr.toString());
});
test('preserves child exit code', () => {
  assert.equal(spawnSync(lock, ['bash', '-c', 'exit 23'], { env: environment() }).status, 23);
});
test('TERM reaches child group before releasing the lock', async () => {
  const env = environment();
  const ready = path.join(env.HOME, 'ready');
  const stopped = path.join(env.HOME, 'stopped');
  const child = spawn(lock, ['bash', '-c', 'trap \'echo stopped > "$2"; exit 0\' TERM; touch "$1"; while :; do sleep 0.1; done', '_', ready, stopped], { env });
  child.stdout.resume(); child.stderr.resume();
  const done = new Promise(resolve => child.on('close', (code, signal) => resolve({code, signal})));
  for (let i = 0; i < 100 && !existsSync(ready); i++) await new Promise(r => setTimeout(r, 20));
  assert.ok(existsSync(ready), 'child started');
  child.kill('SIGTERM');
  assert.equal((await done).signal, 'SIGTERM');
  assert.ok(existsSync(stopped), 'child received TERM');
  assert.ok(!existsSync(path.join(env.HOME, '.picsee/locks/heavy.lock')), 'released lock');
});
