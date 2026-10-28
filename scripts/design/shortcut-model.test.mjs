// node --test scripts/design/*.test.mjs (run by npm run design:check). Each case changes one source the check reads
// and expects the named disagreement; the first case is the repository as it is.
import test from 'node:test';
import assert from 'node:assert/strict';
import { FILES, check, readRepo } from './shortcut-model.mjs';

const withChange = (file, edit) => f => (f === file ? edit(readRepo(f)) : readRepo(f));
const replaceOnce = (from, to) => source => {
  assert.ok(source.includes(from), `fixture anchor missing: ${from}`);
  return source.replace(from, to);
};
const fails = (read, pattern) => {
  const problems = check(read);
  assert.ok(problems.some(p => pattern.test(p)), `expected ${pattern}, got:\n${problems.join('\n') || '(no problems)'}`);
};

test('the shortcut page equals the implemented commands', () => {
  assert.deepEqual(check(), []);
});

test('a newly implemented CommandID that the page lacks fails', () => {
  const read = withChange(FILES.commandID, s => s
    .replace('case preview, previous,', 'case rotate, preview, previous,')
    .replace('case .preview: " "', 'case .rotate: "r"\n        case .preview: " "')
    .replace('public var isImplemented: Bool { [.preview,', 'public var isImplemented: Bool { [.rotate, .preview,'));
  fails(read, /code implements command:rotate \(R,/);
});

test('a command removed from the implemented set but still on the page fails', () => {
  fails(withChange(FILES.commandID, replaceOnce('.zoomIn, .zoomOut, .search', '.zoomIn, .search')),
    /page lists command:zoomOut .*which the code does not implement/);
});

test('a new keyed menu item fails until the page lists it', () => {
  fails(withChange(FILES.menu, replaceOnce('app.addItem(withTitle: String(localized: "Show All")',
    'app.addItem(withTitle: String(localized: "Print"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "p")\n        app.addItem(withTitle: String(localized: "Show All")')),
  /code implements menu:Print \(⌘P,/);
});

test('a changed modifier mask fails on the row that shows the old keys', () => {
  fails(withChange(FILES.menu, replaceOnce('sidebar.keyEquivalentModifierMask = [.control, .command]',
    'sidebar.keyEquivalentModifierMask = [.option, .command]')),
  /menu:Hide sidebar .* shows ⌃ ⌘ S, the code has ⌥ ⌘ S/);
});

test('a page row with the wrong keys fails', () => {
  fails(withChange(FILES.page, replaceOnce('data-shortcut="menu:Quit Picsee"><span class="name">退出 picsee</span><span class="keys"><kbd>⌘</kbd><kbd>Q</kbd>',
    'data-shortcut="menu:Quit Picsee"><span class="name">退出 picsee</span><span class="keys"><kbd>⌘</kbd><kbd>W</kbd>')),
  /menu:Quit Picsee .* shows ⌘ W, the code has ⌘ Q/);
});

test('a page row for an Edit-menu key is refused', () => {
  fails(withChange(FILES.page, replaceOnce('data-shortcut="menu:Quit Picsee"', 'data-shortcut="menu:Quit Picsee|menu:Undo"')),
    /page lists menu:Undo, which is excluded/);
});

test('a key handler that no longer matches its anchor fails', () => {
  fails(withChange('Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift',
    replaceOnce('if event.keyCode == 48 { onTab?(', 'if event.keyCode == 49 { onTab?(')),
  /key:viewer-tab: .*CanvasView\.swift no longer matches/);
});

test('a key equivalent in a shape the parser does not read fails', () => {
  fails(withChange(FILES.menu, replaceOnce('let recentItem = NSMenuItem(title: String(localized: "Open Recent"), action: nil, keyEquivalent: "")',
    'let recentItem = NSMenuItem(title: String(localized: "Open Recent"), action: nil, keyEquivalent: "r")')),
  /found \d+ literal key equivalents .* but parsed \d+/);
});
