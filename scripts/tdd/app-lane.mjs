#!/usr/bin/env node
/** Run the compiled App test bundle for an App-level RED receipt. Build it first. */
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const lock = fileURLToPath(new URL("../heavy-lock.sh", import.meta.url));
const bundle = ".build/dd-ci/Build/Products/Debug/PicseeAppTests.xctest";
const run = spawnSync(lock, ["xcrun", "xctest", bundle], {
  encoding: "utf8", maxBuffer: 16 * 1024 * 1024, timeout: 2100000,
  env: { ...process.env, SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH: "1" },
});
const stdout = run.stdout ?? "", stderr = run.stderr ?? "";
process.stdout.write(stdout);
process.stderr.write(stderr);
const output = `${stdout}\n${stderr}`;
const rootDone = /Test Suite 'All tests' (?:passed|failed) at /.test(output) &&
  /Executed \d+ tests?, with \d+ failures? \(\d+ unexpected\)/.test(output);
const starts = [...output.matchAll(/^◇ Test run started\.$/gm)];
const summaries = [...output.matchAll(/^[✔✘] Test run with (\d+) tests? in \d+ suites? (passed|failed) after .+ seconds(?:\.| with \d+ issues?\.)$/gm)];
const passed = [...output.matchAll(/^✔ Test (?!run with ).+ passed after /gm)].length;
const failed = [...output.matchAll(/^✘ Test (?!run with ).+ failed after /gm)].length;
const skipped = [...output.matchAll(/^➜ Test .+ skipped(?::| after |\.)/gm)].length;
const count = summaries.length === 1 ? Number(summaries[0][1]) : 0;
if (run.error || run.signal || !rootDone || starts.length !== 1 || summaries.length !== 1 || !count ||
    passed + failed + skipped !== count || (summaries[0][2] === "failed") !== (failed > 0) ||
    ![0, 1].includes(run.status) || (run.status === 0) !== (failed === 0)) {
  process.stderr.write("app-lane: no reliable completed App test result; environment failure\n");
  process.exitCode = 70;
} else {
  process.stdout.write(`\nTests run: ${count}, Failures: ${failed}, Errors: 0, Skipped: ${skipped}\n`);
  process.exitCode = run.status;
}
