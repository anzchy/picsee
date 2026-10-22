import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, existsSync, writeFileSync, rmSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const root = process.cwd();
const scratch = mkdtempSync(path.join(os.tmpdir(), 'picsee-lock-tests-'));
after(() => rmSync(scratch, { recursive: true, force: true }));
const lock = path.join(root, 'scripts/heavy-lock.sh');
function environment() {
  const home = mkdtempSync(path.join(scratch, 'lock-'));
  return { ...process.env, HOME: home, PICSEE_HEAVY_LOCK: path.join(home, '.picsee/locks/heavy.lock'), PICSEE_MDPRO_LOCK: path.join(home, 'mdpro.lock'), MDPRO_HEAVY_LOCK_HELD: '', PICSEE_HEAVY_LOCK_WAIT_SECS: '15', PICSEE_HEAVY_LOCK_HELD: '' };
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
test('lock wait timeout keeps exit 75 without entering the command', async () => {
  const env=environment();
  const ready=path.join(env.HOME,'ready');
  const holder=start(['bash','-c','touch "$1"; sleep 4','_',ready],env);
  try {
    await until(()=>existsSync(ready),'holder owns kernel lock');
    const waiting=await run(['bash','-c','echo must-not-run'],{...env,PICSEE_HEAVY_LOCK_WAIT_SECS:'1'});
    assert.equal(waiting.code,75);
    assert.doesNotMatch(waiting.output,/must-not-run/);
  } finally {
    holder.child.kill('SIGTERM');
    await holder.done;
  }
});

// Shared-lock contract: every path is private to this test's temporary directory.
function fakeHolder(env, pid) {
  mkdirSync(env.PICSEE_MDPRO_LOCK);
  writeFileSync(path.join(env.PICSEE_MDPRO_LOCK, 'owner'), `pid=${pid}\nstarted=fixture\ncwd=/fixture\ncmd=sleep\n`);
}
function releaseFake(env) { rmSync(env.PICSEE_MDPRO_LOCK, { recursive: true, force: true }); }
const pause = ms => new Promise(r => setTimeout(r, ms));
test('AC-1 live mdpro holder blocks picsee until release', async () => {
  const env=environment(), ready=path.join(env.HOME,'ready');
  const sleeper=spawn('sleep',['20']);
  fakeHolder(env,sleeper.pid);
  const job=start(['touch',ready],env);
  try {
    await pause(250);
    assert.equal(existsSync(ready),false);
    assert.match(job.output(),/held by:.*pid=/);
  } finally { releaseFake(env); sleeper.kill(); await job.done; }
  assert.ok(existsSync(ready));
});
test('AC-2 shared owner is live and describes the job; exits and signal propagate', async () => {
  for (const ending of ['exit 0','exit 3','kill -TERM $$']) {
    const env=environment(), ready=path.join(env.HOME,'ready'), release=path.join(env.HOME,'release');
    const job=start(['bash','-c',`touch "$1"; while ! test -f "$2"; do sleep 0.02; done; ${ending}`,'_',ready,release],env);
    try {
      await until(()=>existsSync(ready),'job started');
      const owner=readFileSync(path.join(env.PICSEE_MDPRO_LOCK,'owner'),'utf8');
      const pid=Number(owner.match(/^pid=(\d+)$/m)[1]);
      process.kill(pid,0);
      assert.equal(pid,job.child.pid);
      assert.ok(owner.includes(`cwd=${root}\n`));
      assert.match(owner,/^cmd=bash /m);
      assert.match(owner,/^started=.+/m);
    } finally { writeFileSync(release,''); await job.done; }
    const result=await job.done;
    assert.equal(result.code,ending==='exit 0'?0:ending==='exit 3'?3:null);
    assert.equal(result.signal,ending.startsWith('kill')?'SIGTERM':null);
    assert.equal(existsSync(env.PICSEE_MDPRO_LOCK),false);
  }
});
test('AC-3 stale and ownerless mdpro locks are reclaimed', async () => {
  for (const ownerless of [false,true]) {
    const env=environment();
    const dead=spawn('true'); await new Promise(r=>dead.on('close',r));
    fakeHolder(env,dead.pid);
    if(ownerless) rmSync(path.join(env.PICSEE_MDPRO_LOCK,'owner'));
    const result=await run(['true'],env);
    assert.equal(result.code,0,result.output);
    assert.match(result.output,/reclaiming/);
    assert.equal(existsSync(env.PICSEE_MDPRO_LOCK),false);
  }
});
test('AC-4 INT and TERM keep shared lock through group kill grace', async () => {
  for(const sig of ['SIGINT','SIGTERM']) {
    const env={...environment(),PICSEE_HEAVY_LOCK_KILL_GRACE_SECS:'0.5'};
    const ready=path.join(env.HOME,'ready');
    const job=start(['python3','-c','import signal,time,pathlib,sys; signal.signal(signal.SIGTERM,signal.SIG_IGN); pathlib.Path(sys.argv[1]).write_text(str(__import__("os").getpid())); time.sleep(3)',ready],env);
    await until(()=>existsSync(ready),'ignoring child started');
    const pid=Number(readFileSync(ready,'utf8'));
    try {
      job.child.kill(sig); await pause(150);
      process.kill(pid,0);
      assert.ok(existsSync(env.PICSEE_MDPRO_LOCK),'held while child ignores TERM');
    } finally { await job.done; }
    assert.equal((await job.done).signal,sig);
    assert.throws(()=>process.kill(pid,0),{code:'ESRCH'});
    assert.equal(existsSync(env.PICSEE_MDPRO_LOCK),false);
  }
});
test('AC-5 shared timeout exits 75 and releases picsee flock', async () => {
  const env=environment(); fakeHolder(env,process.pid);
  try {
    const result=await run(['echo','must-not-run'],{...env,PICSEE_HEAVY_LOCK_WAIT_SECS:'0.2'});
    assert.equal(result.code,75,result.output);
    assert.doesNotMatch(result.output,/must-not-run/);
    assert.equal((await run(['true'],{...env,PICSEE_MDPRO_LOCK:'off',PICSEE_HEAVY_LOCK_WAIT_SECS:'0.2'})).code,0);
    assert.ok(existsSync(env.PICSEE_MDPRO_LOCK),'live peer never reclaimed');
  } finally { releaseFake(env); }
});
test('AC-6 opt-out and direct nesting export mdpro held flag', async () => {
  for(const direct of [false,true]) {
    const env={...environment(),PICSEE_MDPRO_LOCK:'off',PICSEE_HEAVY_LOCK_HELD:direct?'1':''};
    const result=await run(['bash','-c','test "$MDPRO_HEAVY_LOCK_HELD" = 1'],env);
    assert.equal(result.code,0,result.output);
    assert.equal(existsSync(env.PICSEE_HEAVY_LOCK),!direct);
  }
});
const mdproLock='/Users/jackcheng/Documents/01_Coding/mac-app/mdpro/scripts/heavy-lock.sh';
test('AC-7 real mdpro script serializes in both directions', {timeout:30000}, async () => {
  for(const first of ['picsee','mdpro']) {
    const env=environment(), events=path.join(env.HOME,'events');
    env.MDPRO_HEAVY_LOCK=env.PICSEE_MDPRO_LOCK;
    function launch(which,args) {
      const child=spawn(which==='picsee'?lock:mdproLock,args,{env,cwd:root});
      let output=''; child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b);
      return new Promise((resolve,reject)=>{child.on('error',reject);child.on('close',(code,signal)=>resolve({code,signal,output}));});
    }
    const holder=launch(first,['bash','-c','echo "$2-start $(date +%s)" >> "$1"; sleep 5; echo "$2-end $(date +%s)" >> "$1"','_',events,first]);
    await until(()=>existsSync(events),'first job started');
    const second=first==='picsee'?'mdpro':'picsee';
    const waiter=launch(second,['bash','-c','echo "$2-date $(date +%s)" >> "$1"','_',events,second]);
    const results=await Promise.all([holder,waiter]);
    console.log(`AC-7 ${first} first:\n${readFileSync(events,'utf8')}${results.map(r=>r.output).join('')}`);
    assert.deepEqual(results.map(r=>r.code),[0,0]);
    assert.deepEqual(readFileSync(events,'utf8').trim().split('\n').map(s=>s.split(' ')[0]),[`${first}-start`,`${first}-end`,`${second}-date`]);
  }
});
