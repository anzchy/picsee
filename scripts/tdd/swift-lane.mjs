/**
 * Swift receipt adapter, adapted from mdpro scripts/cargo-test-lane.mjs @9f133f1d.
 * Usage: node scripts/tdd/swift-lane.mjs [filter]
 * Or set PICSEE_SWIFT_FILTER for receipt.js record AND verify (env is inherited).
 * Always runs SwiftPM under the picsee heavy lock. No filter => 64; no completed
 * tests / compile failure / inconsistent outcome => 70 (runner-error/environment).
 * Completed assertion failure => 1 plus Maven counts; pass => 0 plus counts.
 * Keeps raw-byte streaming, backpressure, per-stream decoding and signal relay
 * from the copied adapter. XCTest suite summaries repeat: take the last one,
 * then add Swift Testing's distinct run, including its zero-test companion.
 * Counts failing tests, not Swift Testing issues or repeated XCTest suites.
 * An xcodebuild/UI lane is intentionally not implemented yet.
 */
import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { StringDecoder } from "node:string_decoder";
import { fileURLToPath, pathToFileURL } from "node:url";
const SIGNAL_EXIT_BASE = 128;
const FORWARDED_SIGNALS = ["SIGINT", "SIGTERM", "SIGHUP"];

// Only completed summaries prove tests actually ran. Each stream is parsed
// independently so interleaved partial stdout/stderr cannot forge a summary.
function parseOutput(text) {
  const clean = text.replace(/\x1b\[[0-9;]*m/g, "").replace(/\r/g, "");
  const lines = clean.split("\n");
  const xct = [...clean.matchAll(/^\s*Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures? \(\d+ unexpected\)/gm)].at(-1);
  const swift = [...clean.matchAll(/^[✔✘] Test run with (\d+) tests? in \d+ suites? (passed|failed) after .+ seconds(?:\.| with \d+ issues?\.)$/gm)].at(-1);
  const failures = new Set(lines.filter(l => /^✘ Test (?!run with ).+ failed after /.test(l)).map(l => l.split(' failed after ')[0]));
  const skips = new Set(lines.filter(l => /^➜ Test .+ skipped(?::| after |\.)/.test(l)).map(l => l.split(' skipped')[0]));
  const cases = new Set(lines.filter(l => /^Test Case '.+' failed \(/.test(l)).map(l => l.split("' failed (")[0]));
  // Some XCTest outputs emit errors before the case summary. Never treat a
  // compiler's 'error:' as a failed test: a completed Executed summary is required.
  const errors = new Set([...clean.matchAll(/error: (-\[[^\]]+\]) : /g)].map(m => m[1]));
  if (!xct && !swift) return null;
  const total = +(xct?.[1] || 0) + +(swift?.[1] || 0);
  const failed = (xct ? (cases.size || errors.size || +xct[3]) : 0) + (swift ? failures.size : 0);
  const skipped = +(xct?.[2] || 0) + (swift ? skips.size : 0);
  if (swift && ((swift[2] === 'failed') !== (failures.size > 0))) return null;
  if (!total || failed + skipped > total) return null;
  return {total, failed, skipped};
}
function createDetector() {
  let text = "";
  return { push: chunk => { text += chunk; }, seen: () => parseOutput(text) };
}
/**
 * Write `src` through to `dest` as raw bytes, honouring backpressure, while a
 * per-stream decoder feeds `detector`. EOF ends the last line.
 * @param {import("node:stream").Readable} src
 * @param {NodeJS.WriteStream} dest
 * @param {ReturnType<typeof createFailedSummaryDetector>} detector
 */
function pipeThrough(src, dest, detector) {
  const decoder = new StringDecoder("utf8");
  src.on("data", (/** @type {Buffer} */ chunk) => {
    detector.push(decoder.write(chunk));
    if (!dest.write(chunk)) {
      src.pause();
      dest.once("drain", () => src.resume());
    }
  });
  src.on("end", () => detector.push(`${decoder.end()}\n`));
}

/** Run `then` once everything already written to stdout and stderr is flushed. */
function afterDrain(then) {
  process.stdout.write("", () => process.stderr.write("", then));
}

/**
 * Die by `signal`, as the child did. The exit code is the fallback if the
 * signal does not terminate us.
 * @param {string} signal
 */
function reraise(signal) {
  const n = os.constants.signals[/** @type {NodeJS.Signals} */ (signal)] ?? 0;
  process.exitCode = SIGNAL_EXIT_BASE + n;
  process.kill(process.pid, /** @type {NodeJS.Signals} */ (signal));
}

/** argv is only a filter, never shell code or arbitrary runner arguments. */
function main(argv) {
  const filter = argv[0] ?? process.env.PICSEE_SWIFT_FILTER;
  if (argv.length > 1 || !filter?.trim()) {
    process.stderr.write("usage: node scripts/tdd/swift-lane.mjs [filter]; or set PICSEE_SWIFT_FILTER for record and verify\n");
    process.exitCode = 64;
    return;
  }
  const lock = fileURLToPath(new URL("../heavy-lock.sh", import.meta.url));
  const child = spawn(lock, ["swift", "test", "--package-path", "Packages/PicseeKit", "--filter", filter], { stdio: ["inherit", "pipe", "pipe"] });
  const stdoutDetector = createDetector();
  const stderrDetector = createDetector();
  pipeThrough(child.stdout, process.stdout, stdoutDetector);
  pipeThrough(child.stderr, process.stderr, stderrDetector);
  const forwarders = FORWARDED_SIGNALS.map(sig => [sig, () => child.kill(sig)]);
  for (const [sig, handler] of forwarders) process.on(sig, handler);
  let settled = false;
  const settle = () => {
    settled = true;
    for (const [sig, handler] of forwarders) process.off(sig, handler);
  };
  child.on("error", error => {
    if (settled || child.pid !== undefined) return;
    settle();
    process.stderr.write(`swift-lane: ${error.message}\n`);
    process.exitCode = 127;
  });
  child.on("close", (code, signal) => {
    if (settled) return;
    settle();
    if (signal) { afterDrain(() => reraise(signal)); return; }
    const out = stdoutDetector.seen();
    const err = stderrDetector.seen();
    // SwiftPM writes complete test output to stdout. Accept stderr-only fixtures
    // too, but fail closed on two separate completed result streams.
    const counts = out && err ? null : out || err;
    if (!counts || (code !== 0 && code !== 1) || ((code === 0) !== (counts.failed === 0))) {
      process.stderr.write("swift-lane: no reliable completed test result; environment failure\n");
      process.exitCode = 70;
      return;
    }
    process.stdout.write(`\nTests run: ${counts.total}, Failures: ${counts.failed}, Errors: 0, Skipped: ${counts.skipped}\n`);
    process.exitCode = code;
  });
}
if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) main(process.argv.slice(2));
