import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../../', import.meta.url));
const rules = '.codex/rules/picsee.rules';
const app = 'Picsee.app';
const file = 'Picsee.entitlements';
const key = 'com.apple.security.app-sandbox';

function decision(argv) {
  // Only execpolicy runs; argv is data, never executed or passed through a shell.
  const result = spawnSync('codex', ['execpolicy', 'check', '--rules', rules, '--', ...argv], {
    cwd: root, encoding: 'utf8', timeout: 10_000,
  });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const output = JSON.parse(result.stdout);
  assert.ok(Array.isArray(output.matchedRules), result.stdout);
  return output;
}

const forbidden = [
  ['tccutil', 'reset', 'All'],
  ['tccutil', 'reset', 'All', 'io.github.anzchy.picsee'],
  ['tccutil', 'reset', 'SystemPolicyAllFiles'],
  ['codesign', '--remove-signature', app],
];
// PlistBuddy takes its entire operation as ONE argv token. Cover both executable
// spellings, optional root colon, Set/Add boolean spellings, and Delete.
for (const tool of ['PlistBuddy', '/usr/libexec/PlistBuddy']) {
  for (const entry of [key, `:${key}`]) {
    forbidden.push([tool, '-c', `Delete ${entry}`, file]);
    for (const value of ['false', 'true', '0', '1', 'NO', 'YES']) {
      forbidden.push([tool, '-c', `Set ${entry} ${value}`, file]);
      forbidden.push([tool, '-c', `Add ${entry} bool ${value}`, file]);
    }
  }
}
// plutil key mutations: trailing value/type/file tokens do not affect the ban.
for (const tool of ['plutil', '/usr/bin/plutil']) {
  forbidden.push([tool, '-remove', key, file]);
  for (const operation of ['-replace', '-insert']) {
    for (const value of ['NO', 'YES']) {
      forbidden.push([tool, operation, key, '-bool', value, file]);
    }
    forbidden.push([tool, operation, key, '-json', 'false', file]);
  }
}

const allowed = [
  ['tccutil', '--help'],
  ['codesign', '-d', '--entitlements', ':-', app],
  ['codesign', '--verify', '--deep', '--strict', app],
  ['codesign', '--force', '--sign', 'Apple Development', '--entitlements', file, app],
  ['plutil', '-p', file],
  ['/usr/bin/plutil', '-p', file],
  ['PlistBuddy', '-c', 'Print', file],
  ['/usr/libexec/PlistBuddy', '-c', 'Print', file],
  ['/usr/libexec/PlistBuddy', '-c', `Print :${key}`, file],
  ['plutil', '-replace', 'unrelated.key', '-bool', 'NO', file],
  ['/usr/libexec/PlistBuddy', '-c', 'Set :unrelated.key false', file],
];

for (const argv of forbidden) {
  test(`forbidden: ${JSON.stringify(argv)}`, () => {
    assert.equal(decision(argv).decision, 'forbidden');
  });
}
for (const argv of allowed) {
  test(`allowed: ${JSON.stringify(argv)}`, () => {
    const output = decision(argv);
    assert.notEqual(output.decision, 'forbidden');
    assert.ok(!output.matchedRules.some(rule => rule.prefixRuleMatch?.decision === 'forbidden'));
  });
}

// Replay every embedded example, including all pre-existing ones. These simple
// examples use shell quotes but no expansions; no shell process is involved.
const source = readFileSync(new URL('../../.codex/rules/picsee.rules', import.meta.url), 'utf8');
for (const block of source.matchAll(/^    (match|not_match) = (\[[^\n]*\]),$/gm)) {
  const expectedForbidden = block[1] === 'match';
  for (const example of JSON.parse(block[2])) {
    const argv = [...example.matchAll(/'([^']*)'|"([^"]*)"|([^\s]+)/g)]
      .map(part => part[1] ?? part[2] ?? part[3]);
    test(`embedded ${block[1]}: ${example}`, () => {
      assert.equal(decision(argv).decision === 'forbidden', expectedForbidden);
    });
  }
}
