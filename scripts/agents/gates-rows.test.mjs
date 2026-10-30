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

function assertAmbiguous(t, summary) {
  const result = runRows(t, summary, ['--head', head]);
  assert.equal(result.status, 0, result.stderr);
  const rows = result.stdout.trim().split('\n');
  assert.equal(rows.length, 6);
  for (const row of rows) assert.match(row, new RegExp(`\\| NOT VERIFIED \\| ${head} \\| owner-gates summary ambiguous \\|$`));
  assert.doesNotMatch(result.stdout, /\| PASS \|/);
}

test('gates-rows rejects duplicate lane keys as ambiguous', t => {
  assertAmbiguous(t, complete.replace('node=0\n', 'node=0\nnode=1\n'));
});

test('gates-rows rejects two concatenated runs as ambiguous', t => {
  assertAmbiguous(t, complete + complete.replaceAll(head, 'b'.repeat(40)));
});

test('gates-rows rejects DONE followed by another record as ambiguous', t => {
  assertAmbiguous(t, complete + 'late=1\n');
});

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

test('PR-body workflow lints edits with the trusted base lint and PR-head data', async () => {
  const { readFileSync } = await import('node:fs');
  const workflow = readFileSync(new URL('../../.github/workflows/pr-body.yml', import.meta.url), 'utf8');
  const ci = readFileSync(new URL('../../.github/workflows/ci.yml', import.meta.url), 'utf8');
  assert.match(workflow, /on:\n  pull_request:\n    types: \[opened, edited, synchronize, reopened\]/);
  assert.match(workflow, /permissions:\n  contents: read/);
  assert.match(workflow, /concurrency:\n  group: \$\{\{ github\.workflow \}\}-\$\{\{ github\.event\.pull_request\.number \}\}\n  cancel-in-progress: true/);
  assert.doesNotMatch(ci, /^  pr-body-lint:/m);
  const job = workflow.match(/^  pr-body-lint:\n([\s\S]*?)(?=^  [a-z][a-z-]*:\n|$(?![\s\S]))/m)?.[1];
  assert.ok(job, 'missing pr-body-lint job');
  assert.match(job, /if: github\.event_name == 'pull_request'/);
  assert.match(job, /- name: Checkout trusted base[\s\S]*?ref: \$\{\{ github\.event\.pull_request\.base\.sha \}\}[\s\S]*?path: trusted/);
  assert.match(job, /- name: Checkout PR head[\s\S]*?ref: \$\{\{ github\.event\.pull_request\.head\.sha \}\}[\s\S]*?path: pr-head/);
  assert.match(job, /actions\/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4\.4\.0/);
  assert.match(job, /- name: Test agent tooling\n        working-directory: pr-head\n        run: node --test scripts\/agents\/\*\.test\.mjs/);
  assert.match(job, /- name: Check PR body gates\n        working-directory: pr-head/);
  assert.match(job, /PR_BODY: \$\{\{ github\.event\.pull_request\.body \}\}/);
  assert.match(job, /grep -q '\^export function checkGates' \.\.\/trusted\/scripts\/agents\/ui-parity-pr-body-lint\.mjs/);
  assert.match(job, /trusted PR-body lint lacks checkGates/);
  assert.match(job, /printf '%s' "\$PR_BODY" > "\$RUNNER_TEMP\/pr-body\.md"/);
  assert.match(job, /node \.\.\/trusted\/scripts\/agents\/ui-parity-pr-body-lint\.mjs --base origin\/main --body-file "\$RUNNER_TEMP\/pr-body\.md"/);
  const shell = [...job.matchAll(/run: \|\n((?:        .*\n?)+)/g)].map(match => match[1]).join('\n');
  assert.doesNotMatch(shell, /\$\{\{\s*github\.event\.pull_request\.body/);
  assert.doesNotMatch(job, /xcode/i);
});

test('pre-Gates baseline lint fails the trusted guard', async t => {
  const { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } = await import('node:fs');
  const { execFileSync } = await import('node:child_process');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const workflow = readFileSync(new URL('../../.github/workflows/pr-body.yml', import.meta.url), 'utf8');
  const checkStep = workflow.match(/- name: Check PR body gates\n([\s\S]*)$/)?.[1];
  assert.ok(checkStep, 'missing Check PR body gates step');
  const indentedShell = checkStep.match(/run: \|\n((?:          .*\n?)+)/)?.[1];
  assert.ok(indentedShell, 'missing trusted lint shell');
  const shell = indentedShell.split('\n').filter(Boolean).map(line => line.slice(10)).join('\n');
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const baseline = execFileSync('git', ['show', '3de39c60:scripts/agents/ui-parity-pr-body-lint.mjs'], { cwd: root, encoding: 'utf8' });
  assert.doesNotMatch(baseline, /^export function checkGates/m);
  const directory = mkdtempSync(join(tmpdir(), 'picsee-trusted-lint-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  mkdirSync(join(directory, 'trusted/scripts/agents'), { recursive: true });
  mkdirSync(join(directory, 'pr-head'));
  writeFileSync(join(directory, 'trusted/scripts/agents/ui-parity-pr-body-lint.mjs'), baseline);
  const result = spawnSync('bash', ['-eu', '-c', shell], {
    cwd: join(directory, 'pr-head'),
    env: { ...process.env, PR_BODY: '## Summary\n', RUNNER_TEMP: directory },
    encoding: 'utf8',
  });
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stderr, /trusted PR-body lint lacks checkGates/);
  assert.doesNotMatch(result.stdout, /UI-Parity PR body: PASS/);
});

test('GitHub Actions pins every remote uses line to a SHA with a version comment', async () => {
  const { readFileSync, readdirSync } = await import('node:fs');
  const directory = new URL('../../.github/workflows/', import.meta.url);
  for (const file of readdirSync(directory).filter(file => file.endsWith('.yml'))) {
    const lines = readFileSync(new URL(file, directory), 'utf8').split(/\r?\n/);
    for (const line of lines.filter(line => /^\s*uses:/.test(line))) {
      if (/^\s*uses: \.\//.test(line)) continue;
      assert.match(line, /^\s*uses: \S+@[0-9a-f]{40} # v\S+$/, `${file}: ${line.trim()}`);
    }
  }
});
