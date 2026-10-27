import { test } from 'node:test';
import assert from 'node:assert/strict';
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
