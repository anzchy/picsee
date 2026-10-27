#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const isUIFile = file => file.startsWith('App/UI/') ||
  file.startsWith('Packages/PicseeKit/Sources/PicseeMacUI/');

export function checkUIParity(body, files) {
  if (!files.some(isUIFile)) return { ok: true };
  const section = body.match(/^## UI-Parity\s*$([\s\S]*?)(?=^##\s|$(?![\s\S]))/m)?.[1] ?? '';
  const lines = section.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  for (let i = 0; i + 2 < lines.length; i++) {
    const header = lines[i].split('|').slice(1, -1).map(value => value.trim());
    const rule = lines[i + 1].split('|').slice(1, -1).map(value => value.trim());
    const row = lines[i + 2].split('|').slice(1, -1).map(value => value.trim());
    if (header.length >= 2 && rule.length === header.length && row.length === header.length &&
        rule.every(value => /^:?-{3,}:?$/.test(value)) && row.every(Boolean)) return { ok: true };
  }
  return { ok: false, reason: 'UI files changed; PR body needs a populated ## UI-Parity table' };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const args = process.argv.slice(2);
  const bodyAt = args.indexOf('--body-file');
  const baseAt = args.indexOf('--base');
  if (bodyAt < 0 || !args[bodyAt + 1] || baseAt < 0 || !args[baseAt + 1] ||
      !/^[A-Za-z0-9._/-]+$/.test(args[baseAt + 1]) || args[baseAt + 1].includes('..')) {
    console.error('usage: node scripts/agents/ui-parity-pr-body-lint.mjs --base main --body-file /path/to/body.md');
    process.exitCode = 2;
  } else {
    try {
      const base = execFileSync('git', ['merge-base', args[baseAt + 1], 'HEAD'], { encoding: 'utf8' }).trim();
      const files = execFileSync('git', ['diff', '--name-only', '--diff-filter=ACMR', `${base}..HEAD`], { encoding: 'utf8' }).trim().split('\n');
      const result = checkUIParity(readFileSync(args[bodyAt + 1], 'utf8'), files);
      if (!result.ok) { console.error(result.reason); process.exitCode = 1; }
      else console.log('UI-Parity PR body: PASS');
    } catch (error) {
      console.error(error.message);
      process.exitCode = 2;
    }
  }
}
