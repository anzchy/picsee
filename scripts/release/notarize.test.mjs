import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const script = new URL("./notarize.sh", import.meta.url).pathname;
const credentials = { APPLE_ID: "owner@example.com", APPLE_APP_SPECIFIC_PASSWORD: "abcd-efgh-ijkl-mnop", DEVELOPMENT_TEAM: "GRT84NAK4T" };

/** Runs notarize.sh with a fake xcrun that records its arguments and answers with `status`. */
function run(status, env = credentials) {
  const dir = mkdtempSync(join(tmpdir(), "picsee-notarize-"));
  try {
    const calls = join(dir, "calls.txt");
    writeFileSync(join(dir, "xcrun"), `#!/bin/bash\nprintf '%s\\n' "$*" >> "${calls}"\n` +
      `if [[ "$2" == submit ]]; then printf '{"id":"0f1e2d3c","status":"${status}","message":"done"}'; fi\n`);
    chmodSync(join(dir, "xcrun"), 0o755);
    const file = join(dir, "Picsee.zip");
    writeFileSync(file, "zip");
    const result = spawnSync("/bin/bash", [script, file], { encoding: "utf8",
      env: { PATH: `${dir}:/usr/bin:/bin`, ...env } });
    let log = "";
    try { log = readFileSync(calls, "utf8"); } catch { log = ""; }
    return { ...result, calls: log.trim().split("\n").filter(Boolean), file };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

test("an Accepted submission passes with the Apple ID contract and --wait", () => {
  const result = run("Accepted");
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, 1);
  assert.equal(result.calls[0], `notarytool submit ${result.file} --apple-id owner@example.com --password abcd-efgh-ijkl-mnop ` +
    "--team-id GRT84NAK4T --wait --output-format json");
  assert.match(result.stdout, /0f1e2d3c: Accepted/);
});

test("any other status fails the run and fetches Apple's log", () => {
  for (const status of ["Invalid", "Rejected", "In Progress"]) {
    const result = run(status);
    assert.equal(result.status, 1, status);
    assert.equal(result.calls.length, 2, status);
    assert.match(result.calls[1], /^notarytool log 0f1e2d3c --apple-id owner@example\.com /);
  }
});

test("missing credentials or file stop before contacting Apple", () => {
  for (const name of Object.keys(credentials)) {
    const env = { ...credentials }; delete env[name];
    const result = run("Accepted", env);
    assert.notEqual(result.status, 0, name);
    assert.deepEqual(result.calls, [], name);
  }
  const missing = spawnSync("/bin/bash", [script, "/no/such/file.zip"], { encoding: "utf8", env: { PATH: "/usr/bin:/bin", ...credentials } });
  assert.equal(missing.status, 2);
});
