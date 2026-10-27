import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkUIParity } from './ui-parity-pr-body-lint.mjs';

const uiFiles = ['App/UI/InspectorPlaceholder.swift', 'App/Commands/CommandMenu.swift', 'Packages/PicseeKit/Sources/PicseeMacUI/States/ViewerStateHost.swift'];
const table = '## UI-Parity\n\n| State | Design | Assertion | Status |\n|---|---|---|---|\n| Empty | abc | test | AUTO-PASS |\n';

test('UI changes require a populated UI-Parity table', () => {
  for (const file of uiFiles) {
    assert.equal(checkUIParity('## Summary\n\nDone\n', [file]).ok, false);
    assert.equal(checkUIParity('## UI-Parity\n\nNo changes\n', [file]).ok, false);
    assert.equal(checkUIParity('## UI-Parity\n\n| State | Status |\n|---|---|\n', [file]).ok, false);
    assert.equal(checkUIParity(table, [file]).ok, true);
  }
});

test('non-App changes do not require the table', () => {
  assert.equal(checkUIParity('', ['scripts/device/device.py']).ok, true);
});

test('per-state status accepts only the contract values and rejects FAIL', () => {
  for (const status of ['AUTO-PASS', 'PENDING(P3-10)', 'NOT VERIFIED']) {
    assert.equal(checkUIParity(table.replace('AUTO-PASS', status), uiFiles).ok, true, status);
  }
  for (const status of ['FAIL', 'PASS', 'PENDING', 'UNKNOWN']) {
    assert.equal(checkUIParity(table.replace('AUTO-PASS', status), uiFiles).ok, false, status);
  }
  assert.equal(checkUIParity(table + '| Broken | abc | test | FAIL |\n', uiFiles).ok, false);
});

test('deletion-only UI diff requires a table through the CLI', t => {
  const repo = mkdtempSync(join(tmpdir(), 'picsee-ui-lint-'));
  t.after(() => rmSync(repo, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: repo, encoding: 'utf8' });
  git('init', '-q', '-b', 'main');
  git('config', 'user.email', 'test@example.invalid');
  git('config', 'user.name', 'Test');
  mkdirSync(join(repo, 'App/UI'), { recursive: true });
  const view = join(repo, 'App/UI/OldView.swift');
  writeFileSync(view, 'struct OldView {}\n');
  git('add', 'App/UI/OldView.swift');
  git('commit', '-qm', 'add view');
  git('branch', 'base');
  unlinkSync(view);
  git('add', 'App/UI/OldView.swift');
  git('commit', '-qm', 'delete view');
  const body = join(repo, 'body.md');
  writeFileSync(body, '## Summary\n\nDeleted old view.\n');
  const script = fileURLToPath(new URL('./ui-parity-pr-body-lint.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [script, '--base', 'base', '--body-file', body],
    { cwd: repo, encoding: 'utf8' });
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stderr, /UI-Parity/);
  writeFileSync(body, table);
  const withoutSmoke = spawnSync(process.execPath, [script, '--base', 'base', '--body-file', body],
    { cwd: repo, encoding: 'utf8' });
  assert.equal(withoutSmoke.status, 1, withoutSmoke.stdout + withoutSmoke.stderr);
  assert.match(withoutSmoke.stderr, /Device-Smoke/);
  writeFileSync(body, table + '\nDevice-Smoke: n/a — test only\n');
  const validExemption = spawnSync(process.execPath, [script, '--base', 'base', '--body-file', body],
    { cwd: repo, encoding: 'utf8' });
  assert.equal(validExemption.status, 0, validExemption.stdout + validExemption.stderr);
  for (const smoke of ['Device-Smoke: n/a —   ', 'Device-Smoke: FAIL abc1234 run=offline — broken path',
    'Device-Smoke: PASS abc1234 run=offline — path\nDevice-Smoke: FAIL abc1234 run=offline — broken path',
    'Device-Smoke: PASS abc1234 run=offline — path\nDevice-Smoke: n/a —   ']) {
    writeFileSync(body, table + '\n' + smoke + '\n');
    const rejected = spawnSync(process.execPath, [script, '--base', 'base', '--body-file', body],
      { cwd: repo, encoding: 'utf8' });
    assert.equal(rejected.status, 1, smoke + rejected.stdout + rejected.stderr);
  }
  writeFileSync(body, table + '\nDevice-Smoke: n/a — no user-visible behavior changed\n');
  const exempt = spawnSync(process.execPath, [script, '--base', 'base', '--body-file', body],
    { cwd: repo, encoding: 'utf8' });
  assert.equal(exempt.status, 0, exempt.stdout + exempt.stderr);
  writeFileSync(body, table + '\nDevice-Smoke: NOT VERIFIED abc1234 run=offline — delegated device run pending\n');
  const valid = spawnSync(process.execPath, [script, '--base', 'base', '--body-file', body],
    { cwd: repo, encoding: 'utf8' });
  assert.equal(valid.status, 0, valid.stdout + valid.stderr);
  git('branch', 'after-ui');
  mkdirSync(join(repo, 'scripts'), { recursive: true });
  writeFileSync(join(repo, 'scripts/check.py'), 'print("ok")\n');
  git('add', 'scripts/check.py');
  git('commit', '-qm', 'add non-App script');
  writeFileSync(body, 'Device-Smoke: n/a — non-App script only\n');
  const nonApp = spawnSync(process.execPath, [script, '--base', 'after-ui', '--body-file', body],
    { cwd: repo, encoding: 'utf8' });
  assert.equal(nonApp.status, 0, nonApp.stdout + nonApp.stderr);
  writeFileSync(body, 'Device-Smoke: n/a —   \n');
  const nonAppMissingReason = spawnSync(process.execPath, [script, '--base', 'after-ui', '--body-file', body],
    { cwd: repo, encoding: 'utf8' });
  assert.equal(nonAppMissingReason.status, 1, nonAppMissingReason.stdout + nonAppMissingReason.stderr);
});

test('rename out of App still checks the deleted App path', t => {
  const repo = mkdtempSync(join(tmpdir(), 'picsee-ui-rename-'));
  t.after(() => rmSync(repo, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: repo, encoding: 'utf8' });
  git('init', '-q', '-b', 'main');
  git('config', 'user.email', 'test@example.invalid');
  git('config', 'user.name', 'Test');
  mkdirSync(join(repo, 'App/Commands'), { recursive: true });
  writeFileSync(join(repo, 'App/Commands/Old.swift'), 'struct Old {}\n');
  git('add', 'App/Commands/Old.swift');
  git('commit', '-qm', 'base');
  git('branch', 'base');
  mkdirSync(join(repo, 'scripts'), { recursive: true });
  git('mv', 'App/Commands/Old.swift', 'scripts/Old.swift');
  git('commit', '-qm', 'move');
  const body = join(repo, 'body.md');
  writeFileSync(body, 'No table\n');
  const script = fileURLToPath(new URL('./ui-parity-pr-body-lint.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [script, '--base', 'base', '--body-file', body],
    { cwd: repo, encoding: 'utf8' });
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stderr, /UI-Parity/);
});
