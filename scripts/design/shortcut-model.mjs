#!/usr/bin/env node
// The shortcut list state page (states/shortcuts.html, #214, layout C) must list exactly the shortcuts the app
// implements: every keyed menu item in the command model, every implemented CommandID, and the declared key handlers
// outside the menus. Run by `npm run design:check`; `node scripts/design/shortcut-model.mjs` runs it alone and exits 1
// when the page and the code disagree. Sources are read through `read(path)` so tests can feed changed copies.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const FILES = {
  commandID: 'Packages/PicseeKit/Sources/PicseeCore/Commands/CommandID.swift',
  menu: 'App/Commands/CommandMenu.swift',
  windowCommands: 'Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ChromeWindowCommands.swift',
  page: 'design/prototypes/picsee-browser/states/shortcuts.html',
};
// Directories searched for key equivalents the parser above does not read; any found fails the check.
const SCAN = ['App', 'Packages/PicseeKit/Sources'];

// Keys handled in keyDown rather than by a menu item. Each anchor must still match its file, or the check fails and
// this list has to be revisited together with the page.
export const KEY_HANDLERS = [
  { id: 'key:grid-arrows', file: 'Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridBrowserView.swift',
    anchor: /case 123: delta = -1\s+case 124: delta = 1\s+case 125: delta = columnStep\s+case 126: delta = -columnStep/,
    keys: ['←', '→', '↑', '↓'] },
  { id: 'key:viewer-tab', file: 'Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift',
    anchor: /if event\.keyCode == 48 \{ onTab\?\(/, keys: ['Tab'] },
];
// Keyed menu items left off the page on purpose. The Edit menu's standard text keys only act in the search field;
// layout C has the three cards 文件与窗口, 网格 and 大图 (spec #212 story 26), none of which holds them.
export const EXCLUDED_MENUS = { edit: 'Edit menu: standard text editing, acts only in the search field' };

const MODIFIERS = [['control', '⌃'], ['option', '⌥'], ['shift', '⇧'], ['command', '⌘']];
const NAMED = { ' ': 'Space', '\r': 'Return', '\u{1b}': 'Esc', '\u{f702}': '←', '\u{f703}': '→', '\u{f700}': '↑', '\u{f701}': '↓', '-': '−', '\t': 'Tab' };

function swiftString(literal) {
  return literal.replace(/\\u\{([0-9a-fA-F]+)\}/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/\\r/g, '\r').replace(/\\t/g, '\t').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
}
const keyGlyph = key => NAMED[key] ?? key.toUpperCase();
const glyphs = (key, modifiers) => MODIFIERS.filter(([m]) => modifiers.includes(m)).map(([, g]) => g).concat(keyGlyph(key));
const listOf = (source, re, what) => {
  const m = source.match(re);
  if (!m) throw Error(`cannot parse ${what}`);
  return m[1].split(',').map(s => s.trim().replace(/^\./, '')).filter(Boolean);
};

/** Every shortcut the code implements, as Map id → { keys, source }. */
export function codeShortcuts(read) {
  const shortcuts = new Map(), problems = [];
  const add = (id, keys, source) => {
    if (shortcuts.has(id)) problems.push(`duplicate shortcut id ${id}`);
    shortcuts.set(id, { keys, source });
  };

  // CommandID: the implemented commands, their default keys and whether they use ⌘.
  const commandID = read(FILES.commandID);
  const implemented = listOf(commandID, /var isImplemented: Bool \{ \[([^\]]*)\]/, 'CommandID.isImplemented');
  const usesCommand = listOf(commandID, /var usesCommand: Bool \{ \[([^\]]*)\]/, 'CommandID.usesCommand');
  const keyBlock = commandID.match(/var defaultKey: String \{([\s\S]*?)\n {4}\}/);
  if (!keyBlock) throw Error('cannot parse CommandID.defaultKey');
  const defaultKey = Object.fromEntries([...keyBlock[1].matchAll(/case \.(\w+): "((?:[^"\\]|\\.|\\u\{[0-9a-fA-F]+\})*)"/g)]
    .map(([, id, literal]) => [id, swiftString(literal)]));
  const menuFilter = commandID.match(/static var menuCommands: \[Self\] \{ allCases\.filter \{ \$0\.isImplemented && \$0 != \.(\w+) \} \}/);
  if (!menuFilter) throw Error('cannot parse CommandID.menuCommands');

  // CommandMenu installs CommandID.menuCommands with defaultKey and ⌘ when usesCommand.
  const menu = read(FILES.menu);
  for (const shape of [/for id in CommandID\.menuCommands \{/, /keyEquivalent: id\.defaultKey\)/,
    /item\.keyEquivalentModifierMask = id\.usesCommand \? \[\.command\] : \[\]/])
    if (!shape.test(menu)) throw Error(`CommandMenu.swift no longer installs CommandID.menuCommands as expected (${shape})`);
  for (const id of implemented) {
    if (!(id in defaultKey)) throw Error(`CommandID.${id} has no defaultKey`);
    // The command left out of menuCommands (search) has its own menu item, parsed below by its title.
    if (id === menuFilter[1]) continue;
    add(`command:${id}`, glyphs(defaultKey[id], usesCommand.includes(id) ? ['command'] : []), FILES.commandID);
  }

  // Menu items with a literal title and a literal, non-empty key equivalent.
  let literalKeys = 0;
  const menuItem = /(?:let (\w+) = )?(\w+)\.addItem\(withTitle: String\(localized: "([^"]+)"\),\s*action: [^\n]*?(?:\n[^\n]*?)?keyEquivalent: "((?:[^"\\]|\\.)*)"\)/g;
  for (const file of [FILES.menu, FILES.windowCommands]) {
    const source = read(file);
    for (const match of source.matchAll(menuItem)) {
      const [, variable, receiver, title, literal] = match;
      const key = swiftString(literal);
      if (!key) continue;
      literalKeys++;
      let modifiers = ['command'];
      if (variable) {
        const mask = source.slice(match.index).match(new RegExp(`\\b${variable}\\.keyEquivalentModifierMask = \\[([^\\]]*)\\]`));
        if (mask) modifiers = mask[1].split(',').map(s => s.trim().replace(/^\./, '')).filter(Boolean);
      }
      const id = `menu:${title}`;
      if (EXCLUDED_MENUS[receiver]) { shortcuts.set(id, { keys: glyphs(key, modifiers), source: file, excluded: EXCLUDED_MENUS[receiver] }); continue; }
      add(id, glyphs(key, modifiers), file);
    }
  }
  // Edit's Cut/Copy/Paste/Select All come from a tuple loop; they are excluded like the rest of Edit.
  const editLoop = menu.match(/for \(title, action, key\) in \[([\s\S]*?)\] \{\s*edit\.addItem/);
  if (editLoop) for (const [, title, key] of editLoop[1].matchAll(/\("([^"]+)", "[^"]+", "([^"]+)"\)/g)) {
    literalKeys++;
    shortcuts.set(`menu:${title}`, { keys: glyphs(key, ['command']), source: FILES.menu, excluded: EXCLUDED_MENUS.edit });
  }

  // Every literal key equivalent in the app must be one parsed above; SwiftUI shortcuts are not parsed at all.
  let found = 0;
  const walk = dir => {
    for (const entry of fs.readdirSync(path.join(root, dir), { withFileTypes: true })) {
      const rel = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(rel);
      else if (entry.name.endsWith('.swift')) {
        const source = read(rel);
        found += [...source.matchAll(/keyEquivalent: "((?:[^"\\]|\\.)+)"/g)].length;
        found += [...source.matchAll(/\("[^"]+", "[^"]+:", "[^"]+"\)/g)].length;
        if (/\.keyboardShortcut\(/.test(source)) problems.push(`${rel} uses .keyboardShortcut, which this check does not read`);
      }
    }
  };
  for (const dir of SCAN) walk(dir);
  if (found !== literalKeys) problems.push(`found ${found} literal key equivalents in ${SCAN.join(', ')} but parsed ${literalKeys}; teach scripts/design/shortcut-model.mjs the new shape`);

  for (const handler of KEY_HANDLERS) {
    if (!handler.anchor.test(read(handler.file))) problems.push(`${handler.id}: ${handler.file} no longer matches ${handler.anchor}`);
    add(handler.id, handler.keys, handler.file);
  }
  return { shortcuts, problems };
}

/** Rows of the page, as [{ ids, name, keys }]. A row lists its ids in data-shortcut, separated by |, and its keys as <kbd>. */
export function pageShortcuts(html) {
  return [...html.matchAll(/<li\b[^>]*\bdata-shortcut="([^"]+)"[^>]*>([\s\S]*?)<\/li>/g)].map(([, ids, body]) => ({
    ids: ids.split('|').map(id => id.trim()),
    name: (body.match(/<span class="name">([^<]*)<\/span>/) || [, ''])[1],
    keys: [...body.matchAll(/<kbd>([^<]+)<\/kbd>/g)].map(m => m[1]),
  }));
}

/** Differences between the code and the page; empty when they agree. */
export function compare({ shortcuts, problems }, rows) {
  const out = [...problems], seen = new Map();
  if (!rows.length) out.push('the page has no data-shortcut rows');
  for (const row of rows) {
    for (const id of row.ids) {
      if (seen.has(id)) out.push(`${id} is listed twice`);
      seen.set(id, row);
      const code = shortcuts.get(id);
      if (!code) out.push(`page lists ${id} (${row.name}), which the code does not implement`);
      else if (code.excluded) out.push(`page lists ${id}, which is excluded: ${code.excluded}`);
    }
    if (row.ids.every(id => shortcuts.has(id))) {
      const want = row.ids.flatMap(id => shortcuts.get(id).keys);
      if (JSON.stringify(want) !== JSON.stringify(row.keys))
        out.push(`${row.ids.join('|')} (${row.name}) shows ${row.keys.join(' ') || 'no keys'}, the code has ${want.join(' ')}`);
    }
  }
  for (const [id, code] of shortcuts) if (!code.excluded && !seen.has(id))
    out.push(`code implements ${id} (${code.keys.join('')}, ${code.source}) but the page does not list it`);
  return out;
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const readRepo = file => fs.readFileSync(path.join(root, file), 'utf8');

export function check(read = readRepo) {
  let html;
  try { html = read(FILES.page); } catch (error) { return [`cannot read ${FILES.page}: ${error.message}`]; }
  return compare(codeShortcuts(read), pageShortcuts(html));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const problems = check();
  if (problems.length) { console.error('shortcut-model FAIL:\n- ' + problems.join('\n- ')); process.exit(1); }
  console.log('shortcut-model PASS');
}
