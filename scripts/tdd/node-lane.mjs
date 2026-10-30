#!/usr/bin/env node
/** Run node --test files for a RED receipt and print a count line the receipt parser understands. */
import { spawnSync } from "node:child_process";

const files = process.argv.slice(2);
if (!files.length) {
  process.stderr.write("usage: node-lane.mjs <test file>…\n");
  process.exit(70);
}
const run = spawnSync(process.execPath, ["--test", "--test-reporter=tap", ...files], {
  encoding: "utf8", maxBuffer: 16 * 1024 * 1024, timeout: 600000,
});
const stdout = run.stdout ?? "", stderr = run.stderr ?? "";
process.stdout.write(stdout);
process.stderr.write(stderr);
const count = (name) => Number(new RegExp(`^# ${name} (\\d+)$`, "m").exec(stdout)?.[1] ?? NaN);
const [total, failed, skipped, cancelled] = ["tests", "fail", "skipped", "cancelled"].map(count);
if (run.error || run.signal || ![total, failed, skipped, cancelled].every(Number.isFinite) || !total ||
    cancelled || ![0, 1].includes(run.status) || (run.status === 0) !== (failed === 0)) {
  process.stderr.write("node-lane: no reliable completed test result; environment failure\n");
  process.exitCode = 70;
} else {
  process.stdout.write(`\nTests run: ${total}, Failures: ${failed}, Errors: 0, Skipped: ${skipped}\n`);
  process.exitCode = run.status;
}
