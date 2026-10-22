import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, existsSync, writeFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const root = process.cwd();
const scratch = mkdtempSync(path.join(os.tmpdir(), 'picsee-lock-tests-'));
after(() => rmSync(scratch, { recursive: true, force: true }));
const lock = path.join(root, 'scripts/heavy-lock.sh');
function environment() {
  const home = mkdtempSync(path.join(scratch, 'lock-'));
  return { ...process.env, HOME: home, PICSEE_HEAVY_LOCK_WAIT_SECS: '15', PICSEE_HEAVY_LOCK_HELD: '' };
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
  const r = spawnSync(lock, ['bash', '-c', 'test "$PICSEE_HEAVY_LOCK_HELD" = 1 && test -f "$HOME/.picsee/locks/heavy.lock"'], { env });
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
  assert.equal((await run(['true'], env)).code, 0, 'lock available after termination');
});
test('HUP stops the command before releasing the lock', async () => {
  const env = environment();
  const ready = path.join(env.HOME, 'ready');
  const stopped = path.join(env.HOME, 'stopped');
  // Natural completion is bounded so a failing baseline leaves no orphan job.
  const child = spawn(lock, ['bash', '-c', 'trap \'echo stopped > "$2"; exit 0\' TERM; touch "$1"; sleep 0.8', '_', ready, stopped], { env });
  child.stdout.resume(); child.stderr.resume();
  const done = new Promise(resolve => child.on('close', (code, signal) => resolve({code, signal})));
  for (let i = 0; i < 100 && !existsSync(ready); i++) await new Promise(r => setTimeout(r, 20));
  assert.ok(existsSync(ready));
  child.kill('SIGHUP');
  assert.equal((await done).signal, 'SIGHUP');
  assert.ok(existsSync(stopped), 'child must receive termination before lock release');
  assert.equal((await run(['true'], env)).code, 0, 'lock available after hangup');
});

async function until(check, message) {
  for (let i = 0; i < 200 && !check(); i++) await new Promise(r => setTimeout(r, 20));
  assert.ok(check(), message);
}
function start(args, env) {
  const child = spawn(lock, args, { env, cwd: root });
  let output = '';
  child.stdout.on('data', b => output += b); child.stderr.on('data', b => output += b);
  const done = new Promise((resolve,reject) => {
    child.on('error',reject);child.on('close',(code,signal) => resolve({code,signal,output}));
  });
  return {child,done,output:()=>output};
}
test('SIGKILLed holder leaves inherited lock held until its child exits, with two waiters', {timeout:25000}, async () => {
  const env=environment();
  const events=path.join(env.HOME,'events');
  const release=path.join(env.HOME,'release');
  const holder=start(['bash','-c','echo holder-start >> "$1"; for ((i=0;i<600;i++)); do test -f "$2" && break; sleep 0.02; done; echo holder-end >> "$1"','_',events,release],env);
  await until(()=>existsSync(events),'holder starts');
  const cmd=['bash','-c','echo start >> "$1"; sleep 0.1; echo end >> "$1"','_',events];
  const waiters=[start(cmd,env),start(cmd,env)];
  try {
    await until(()=>waiters.every(w=>w.output().includes('waiting')),'both waiters queue before kill');
    const exited=new Promise(resolve=>holder.child.on('exit',(code,signal)=>resolve({code,signal})));
    holder.child.kill('SIGKILL');
    assert.equal((await exited).signal,'SIGKILL');
    // The old mkdir implementation polls at five seconds. Cover that boundary.
    await new Promise(r=>setTimeout(r,5500));
    assert.equal(readFileSync(events,'utf8'),'holder-start\n','no waiter enters while inherited descriptor remains open');
  } finally {
    writeFileSync(release,'release');
    await holder.done;
    const result=await Promise.all(waiters.map(w=>w.done));
    assert.deepEqual(result.map(r=>r.code),[0,0]);
  }
  assert.equal(readFileSync(events,'utf8'),'holder-start\nholder-end\nstart\nend\nstart\nend\n');
});
test('three-way contention never overlaps', {timeout:25000}, async () => {
  const env=environment();
  const events=path.join(env.HOME,'events');
  const active=path.join(env.HOME,'active');
  const cmd=['bash','-c','mkdir "$2" || exit 22; echo start >> "$1"; sleep 0.2; echo end >> "$1"; rmdir "$2"','_',events,active];
  const result=await Promise.all([run(cmd,env),run(cmd,env),run(cmd,env)]);
  assert.deepEqual(result.map(r=>r.code),[0,0,0]);
  assert.equal(readFileSync(events,'utf8'),'start\nend\nstart\nend\nstart\nend\n');
});
