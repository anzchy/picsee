#!/usr/bin/env node
import { readFileSync } from 'node:fs';

const lanes = [
  ['package-tests', 'swift'],
  ['package-coverage', 'lcov'],
  ['unsigned-build', 'xcodebuild'],
  ['node-tooling', 'node'],
  ['ledger', 'ledger'],
  ['diff-check', 'diffcheck'],
];
const args = process.argv.slice(2);
if (args.length !== 1 && !(args.length === 3 && args[1] === '--head' && /^[0-9a-f]{7,40}$/i.test(args[2]))) {
  console.error('usage: node scripts/agents/gates-rows.mjs <summary.txt> [--head <sha>]');
  process.exitCode = 2;
} else {
  try {
    const lines = readFileSync(args[0], 'utf8').split(/\r?\n/).map(line => {
      const record = line.match(/^\s*([A-Za-z]+)\s*=\s*(.*?)\s*$/);
      return record ? `${record[1]}=${record[2]}` : line;
    });
    const head = lines.find(line => /^head=[0-9a-f]{7,40}$/i.test(line))?.split('=')[1];
    if (!head) throw new Error('owner-gates summary missing valid head');
    const finalLine = lines.filter(line => line.trim()).at(-1);
    const doneCount = lines.filter(line => line === 'DONE').length;
    const ambiguous = lines.filter(line => line.startsWith('head=')).length > 1 || doneCount > 1 ||
      (doneCount === 1 && finalLine !== 'DONE') ||
      lanes.some(([, key]) => lines.filter(line => line.startsWith(`${key}=`)).length > 1);
    const malformed = lanes.some(([, key]) => {
      const value = lines.find(line => line.startsWith(`${key}=`))?.slice(key.length + 1);
      return value !== undefined && !/^\d+$/.test(value);
    });
    const stale = args.length === 3 && args[2].toLowerCase() !== head.toLowerCase();
    let rows;
    if (ambiguous) {
      rows = lanes.map(([lane]) => `| ${lane} | NOT VERIFIED | ${head} | owner-gates summary ambiguous |`);
    } else if (malformed) {
      rows = lanes.map(([lane]) => `| ${lane} | NOT VERIFIED | ${head} | owner-gates summary malformed |`);
    } else if (finalLine !== 'DONE') {
      rows = lanes.map(([lane]) => `| ${lane} | NOT VERIFIED | ${head} | owner-gates summary incomplete |`);
    } else if (stale) {
      rows = lanes.map(([lane]) => `| ${lane} | NOT VERIFIED | ${head} | owner-gates stale head ${head.slice(0, 7)} |`);
    } else {
      rows = lanes.map(([lane, key]) => {
        const exit = lines.find(line => line.startsWith(`${key}=`))?.slice(key.length + 1);
        if (exit === undefined) return `| ${lane} | NOT RUN | — | owner-gates summary missing ${key} |`;
        const status = exit === '0' ? 'PASS' : 'FAIL';
        return `| ${lane} | ${status} | ${head} | owner-gates ${key}=${exit} |`;
      });
    }
    console.log(rows.join('\n'));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
  }
}
