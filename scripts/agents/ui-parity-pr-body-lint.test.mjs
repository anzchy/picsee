import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkUIParity } from './ui-parity-pr-body-lint.mjs';

const uiFiles = ['App/UI/InspectorPlaceholder.swift', 'Packages/PicseeKit/Sources/PicseeMacUI/States/ViewerStateHost.swift'];
const table = '## UI-Parity\n\n| State | Design | Assertion | Status |\n|---|---|---|---|\n| Empty | abc | test | AUTO-PASS |\n';

test('UI changes require a populated UI-Parity table', () => {
  for (const file of uiFiles) {
    assert.equal(checkUIParity('## Summary\n\nDone\n', [file]).ok, false);
    assert.equal(checkUIParity('## UI-Parity\n\nNo changes\n', [file]).ok, false);
    assert.equal(checkUIParity('## UI-Parity\n\n| State | Status |\n|---|---|\n', [file]).ok, false);
    assert.equal(checkUIParity(table, [file]).ok, true);
  }
});

test('non-UI changes do not require the table', () => {
  assert.equal(checkUIParity('', ['scripts/device/device.py', 'App/Commands/CommandMenu.swift']).ok, true);
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
  const invalidExemption = spawnSync(process.execPath, [script, '--base', 'base', '--body-file', body],
    { cwd: repo, encoding: 'utf8' });
  assert.equal(invalidExemption.status, 1, invalidExemption.stdout + invalidExemption.stderr);
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
});
