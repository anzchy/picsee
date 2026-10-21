import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Keep CLI credentials and installation state in this project, outside version control.
const project = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const child = spawn(process.execPath, [resolve(project, 'node_modules/@google/stitch/dist/stitch.js'), ...process.argv.slice(2)], {
  cwd: project,
  env: { ...process.env, STITCH_CONFIG_DIR: resolve(project, '.stitch-cli') },
  stdio: 'inherit',
});
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exitCode = code ?? 1;
});
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal));
