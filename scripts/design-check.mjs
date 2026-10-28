#!/usr/bin/env node
// npm run design:check — serve design/ and states/ on two local ports, then run scripts/verify_design_catalog.js in
// headless Chromium (Playwright pinned in package-lock.json). Exits 1 when the check fails, 2 when it cannot start.
// Ports: PICSEE_DESIGN_PORT and PICSEE_STATES_PORT, default free ports. PICSEE_DESIGN_SCREENSHOT sets the preview
// screenshot path, default a temporary directory (never the repo).
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const check = require('./verify_design_catalog.js');

const freePort = () => new Promise((resolve, reject) => {
  const server = net.createServer().once('error', reject);
  server.listen(0, '127.0.0.1', () => { const { port } = server.address(); server.close(() => resolve(port)); });
});
const portFrom = async name => {
  const value = process.env[name];
  if (!value) return freePort();
  if (!/^\d+$/.test(value) || +value < 1 || +value > 65535) throw Error(`${name} must be a port number, got ${value}`);
  return +value;
};

const servers = [];
async function serve(directory, port) {
  const child = spawn('python3', ['-m', 'http.server', String(port), '--bind', '127.0.0.1', '--directory', directory],
    { cwd: root, stdio: ['ignore', 'ignore', 'pipe'] });
  servers.push(child);
  let stderr = '';
  child.stderr.on('data', d => { stderr += d; });
  const origin = `http://127.0.0.1:${port}`;
  for (const deadline = Date.now() + 15000; Date.now() < deadline;) {
    if (child.exitCode !== null) throw Error(`http.server for ${directory} exited ${child.exitCode}: ${stderr.trim()}`);
    try { if ((await fetch(origin + '/')).ok) return origin; } catch {}
    await new Promise(r => setTimeout(r, 100));
  }
  throw Error(`http.server for ${directory} did not answer on ${origin}`);
}

let status = 0, browser;
try {
  const { chromium } = await import('playwright');
  const design = await serve('design', await portFrom('PICSEE_DESIGN_PORT'));
  const states = await serve('design/prototypes/picsee-browser/states', await portFrom('PICSEE_STATES_PORT'));
  const screenshot = process.env.PICSEE_DESIGN_SCREENSHOT
    || path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'picsee-design-check-')), 'design-material-preview.png');
  browser = await chromium.launch();
  const page = await browser.newPage();
  try {
    const result = await check(page, { design, states, screenshot });
    console.log(JSON.stringify({ ...result, results: undefined }, null, 1));
    console.log(`design:check PASS (${result.stateCount} states, ${result.hashesPinned} hashes, ${result.subcases} sub-cases, ${result.branchPlays} branch plays)`);
  } catch (error) {
    console.error(`design:check FAIL: ${error.message}`);
    status = 1;
  }
} catch (error) {
  console.error(`design:check could not start: ${error.message}`);
  status = 2;
} finally {
  if (browser) await browser.close();
  for (const child of servers) child.kill();
}
process.exit(status);
