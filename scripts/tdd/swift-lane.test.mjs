import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const root = process.cwd();
const handoff = path.join(process.env.HOME, '.picsee/herdr/gpt-imple-1');
const temp = mkdtempSync(path.join(handoff, 'swift-cli-'));
// Only Swift itself is replaced: the real wrapper and heavy lock execute.
writeFileSync(path.join(temp, 'swift'), `#!${process.execPath}
const fs = require('node:fs');
fs.writeFileSync(process.env.ARGV_FILE, JSON.stringify({argv:process.argv.slice(2), held:process.env.PICSEE_HEAVY_LOCK_HELD}));
const text=fs.readFileSync(process.env.FIXTURE);
// Feed uneven byte chunks (including multibyte checkmarks), across both streams.
const stream = process.env.ON_STDERR ? process.stderr : process.stdout;
for(let i=0;i<text.length;i+=17) stream.write(text.subarray(i,i+17));
process.exitCode=Number(process.env.SWIFT_EXIT);
`, { mode: 0o755 });
const require = createRequire(import.meta.url);
const cache = path.join(process.env.HOME, '.claude/plugins/cache/xiaolai/tdd-guardian');
const version = readdirSync(cache).sort((a,b) => a.localeCompare(b, undefined, {numeric:true})).at(-1);
const plugin = process.env.PICSEE_TDD_PLUGIN_ROOT || path.join(cache, version);
const exec = require(path.join(plugin, 'scripts/tdd-guardian/lib/exec.js'));
const { classifyRedRun } = require(path.join(plugin, 'scripts/tdd-guardian/lib/verification.js'));
function run(fixture, code, { filter = 'FixtureTests/selectedOnly', args = [], stderr = false } = {}) {
  const argvFile = path.join(temp, 'argv.json');
  const env = { ...process.env, PATH: `${temp}:${process.env.PATH}`, PICSEE_SWIFT_FILTER: filter,
    PICSEE_HEAVY_LOCK: path.join(temp, 'heavy.lock'), PICSEE_HEAVY_LOCK_HELD: '',
    ARGV_FILE: argvFile, FIXTURE: path.join(root, 'scripts/tdd/fixtures', fixture + '.txt'),
    SWIFT_EXIT: String(code), ON_STDERR: stderr ? '1' : '' };
  const r = spawnSync(process.execPath, ['scripts/tdd/swift-lane.mjs', ...args], { env, encoding:'utf8', timeout:10000 });
  assert.ifError(r.error);
  return { ...r, argvFile };
}
for (const [fixture, code, expected, kind] of [
  ['swift-pass',0,{total:3,failed:0,passed:2,skipped:1},'green'],
  ['swift-fail',1,{total:3,failed:1,passed:1,skipped:1},'assertion-failure'],
  ['xctest-pass',0,{total:12,failed:0,passed:11,skipped:1},'green'],
  ['xctest-fail',1,{total:12,failed:1,passed:10,skipped:1},'assertion-failure'],
]) {
  test(`${fixture}: counted once, classified ${kind} by real plugin`, () => {
    const r = run(fixture,code,{stderr:fixture.startsWith('xctest')});
    assert.deepEqual(exec.parseCounts(r.stdout,r.stderr),expected);
    assert.equal(r.status,code,r.stderr);
    assert.equal(classifyRedRun({status:exec.classify(r.status,r.stdout,r.stderr),testCounts:exec.parseCounts(r.stdout,r.stderr)}).kind,kind);
    assert.equal((r.stdout.match(/^Tests run:/gm)||[]).length,1);
  });
}
test('compile failure is runner-error/environment with no count line', () => {
  const r = run('compile-fail',1);
  assert.equal(r.status,70);
  assert.equal(exec.parseCounts(r.stdout,r.stderr),null);
  assert.equal(exec.classify(r.status,r.stdout,r.stderr),'runner-error');
  assert.equal(classifyRedRun({status:exec.classify(r.status,r.stdout,r.stderr)}).kind,'environment');
});
test('only the selected filter is passed as a literal argv under the lock', () => {
  const r = run('swift-pass',0,{args:['selected name;$literal']});
  assert.equal(r.status,0,r.stderr);
  assert.deepEqual(JSON.parse(readFileSync(r.argvFile)),{argv:['test','--package-path','Packages/PicseeKit','--filter','selected name;$literal'],held:'1'});
});
test('missing filter fails closed rather than running the full suite', () => {
  const r = run('swift-pass',0,{filter:''});
  assert.equal(r.status,64);
  assert.doesNotMatch(r.stdout,/Tests run:/);
});
test('a runner failure after a completed pass is not assertion RED', () => {
  const r = run('swift-pass',1);
  assert.equal(r.status,70);
  assert.equal(exec.parseCounts(r.stdout,r.stderr),null);
});
