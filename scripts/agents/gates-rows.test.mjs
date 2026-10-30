import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('./gates-rows.mjs', import.meta.url));
const head = '3de39c6012345678901234567890123456789012';
const complete = `head=${head}\nswift=0\nlcov=0\nlines 10/10\nxcodegen=0\nxcodebuild=0\nnode=0\nledger=0\ndiffcheck=0\nDONE\n`;

function runRows(t, summary, args = []) {
  const directory = mkdtempSync(join(tmpdir(), 'picsee-gates-rows-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const file = join(directory, 'summary.txt');
  writeFileSync(file, summary);
  return spawnSync(process.execPath, [script, file, ...args], { encoding: 'utf8' });
}

test('gates-rows converts a complete owner-gates summary to six PASS rows', t => {
  const result = runRows(t, complete, ['--head', head]);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(result.stdout.trim().split('\n'), [
    `| package-tests | PASS | ${head} | owner-gates swift=0 |`,
    `| package-coverage | PASS | ${head} | owner-gates lcov=0 |`,
    `| unsigned-build | PASS | ${head} | owner-gates xcodebuild=0 |`,
    `| node-tooling | PASS | ${head} | owner-gates node=0 |`,
    `| ledger | PASS | ${head} | owner-gates ledger=0 |`,
    `| diff-check | PASS | ${head} | owner-gates diffcheck=0 |`,
  ]);
});

test('gates-rows marks every row NOT VERIFIED without final DONE', t => {
  const result = runRows(t, complete.replace('DONE\n', ''), ['--head', head]);
  assert.equal(result.status, 0, result.stderr);
  const rows = result.stdout.trim().split('\n');
  assert.equal(rows.length, 6);
  for (const row of rows) assert.match(row, new RegExp(`\\| NOT VERIFIED \\| ${head} \\| owner-gates summary incomplete \\|$`));
  assert.doesNotMatch(result.stdout, /\| PASS \|/);
});

test('gates-rows marks every row NOT VERIFIED for a stale summary head', t => {
  const currentHead = 'b'.repeat(40);
  const result = runRows(t, complete, ['--head', currentHead]);
  assert.equal(result.status, 0, result.stderr);
  const rows = result.stdout.trim().split('\n');
  assert.equal(rows.length, 6);
  for (const row of rows) assert.match(row, new RegExp(`\\| NOT VERIFIED \\| ${head} \\| owner-gates stale head ${head.slice(0, 7)} \\|$`));
  assert.doesNotMatch(result.stdout, /\| PASS \|/);
});

test('gates-rows converts a non-zero lane exit to FAIL', t => {
  const result = runRows(t, complete.replace('xcodebuild=0', 'xcodebuild=1'), ['--head', head]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, new RegExp(`^\\| unsigned-build \\| FAIL \\| ${head} \\| owner-gates xcodebuild=1 \\|$`, 'm'));
  assert.equal(result.stdout.match(/\| PASS \|/g).length, 5);
});

test('gates-rows marks a missing key NOT RUN with a reason', t => {
  const result = runRows(t, complete.replace('node=0\n', ''), ['--head', head]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^\| node-tooling \| NOT RUN \| — \| owner-gates summary missing node \|\n/m);
  assert.equal(result.stdout.match(/\| PASS \|/g).length, 5);
});

test('gates-rows rejects a missing summary without emitting PASS', t => {
  const directory = mkdtempSync(join(tmpdir(), 'picsee-gates-rows-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const result = spawnSync(process.execPath, [script, join(directory, 'missing.txt'), '--head', head], { encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /\| PASS \|/);
});
