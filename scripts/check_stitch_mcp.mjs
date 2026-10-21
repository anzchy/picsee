import { spawn } from 'node:child_process';
import { writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

// A real stdio handshake, independent of whether this chat reloads MCP servers.
const child = spawn(process.execPath, [resolve('scripts/stitch.mjs'), 'mcp', 'start'], {
  stdio: ['pipe', 'pipe', 'pipe'],
});
const pending = new Map();
let buffer = '', stderr = '', nextId = 0;
child.stderr.on('data', data => { stderr += data; });
child.stdout.on('data', data => {
  buffer += data;
  while (buffer.includes('\n')) {
    const end = buffer.indexOf('\n');
    const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
    if (!line.trim()) continue;
    const message = JSON.parse(line);
    if (pending.has(message.id)) {
      const { resolve, reject, timer } = pending.get(message.id);
      pending.delete(message.id); clearTimeout(timer);
      message.error ? reject(new Error(JSON.stringify(message.error))) : resolve(message.result);
    }
  }
});
function request(method, params) {
  return new Promise((resolve, reject) => {
    const id = ++nextId;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`${method} timed out`)); }, 25000);
    pending.set(id, { resolve, reject, timer });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
mkdirSync('evidence', { recursive: true });
try {
  const initialize = await request('initialize', {
    protocolVersion: '2024-11-05', capabilities: {},
    clientInfo: { name: 'picsee-stitch-project-check', version: '1.0.0' },
  });
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  const catalog = await request('tools/list', {});
  writeFileSync('evidence/stitch-mcp-handshake.json', JSON.stringify({ initialize, tools: catalog.tools.map(t => ({ name: t.name, description: t.description })) }, null, 2));
  console.log(JSON.stringify({ server: initialize.serverInfo, tools: catalog.tools.length, success: true }));
} finally {
  writeFileSync('evidence/stitch-mcp-stderr.txt', stderr);
  child.stdin.end(); child.kill('SIGTERM');
}
