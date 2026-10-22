/**
 * Purpose: Wraps `cargo test` for the tdd-guardian rust lanes so a red test
 * reads as a test failure, not a broken runner. cargo exits 101 both when a
 * test fails and when the crate does not compile; the plugin reads 101 as
 * `runner-error` and only exit 1 as `fail`. This wrapper exits 1 when cargo
 * exits 101 *and* printed a `test result: FAILED.` summary, and passes every
 * other outcome through unchanged (plan WI-2, Q1).
 *
 * Usage: `scripts/heavy-lock.sh node scripts/cargo-test-lane.mjs cargo test …`
 *
 * Pipeline: spawn argv (no shell, stdin inherited, env inherited)
 *   → each of stdout/stderr: raw Buffer written through live, and decoded by
 *     its own StringDecoder into its own detector
 *   → on the child's `close` (pipes drained): classifyCargoExit → exit code,
 *     or re-raise the child's signal on this process.
 *
 * Key decisions:
 * - Output is written through as raw Buffers, never re-encoded, so invalid
 *   UTF-8 stays byte-identical; detection decodes separately (Deviation 9).
 * - One detector per stream: a summary split across stdout and stderr is not
 *   a summary. The decision waits for `close`, not `exit`, so a summary still
 *   in a pipe is not missed; the exit is set through `process.exitCode` so our
 *   own stdout drains before Node exits.
 * - SIGINT/SIGTERM/SIGHUP are forwarded to the child as themselves. A child
 *   that dies by any signal is re-raised here once our streams drain, with
 *   128+n as the fallback exit code if the re-raise does not kill us.
 * - Exit codes: no arguments → 64 (usage); spawn failure → 127 with
 *   `<cmd>: <message>` on stderr.
 * - Plugin caveats (tdd-guardian 0.10.2): it parses counts from the first
 *   `test result:` line only, so a red in a later test target still exits 1
 *   but records as `opaque-failure`; a doctest that fails to compile prints
 *   `test result: FAILED` and so maps to 1.
 *
 * @module scripts/cargo-test-lane
 * @coordinates-with scripts/heavy-lock.sh (runs this under the machine-wide lock)
 * @coordinates-with .claude/tdd-guardian/config.json (`rust`, `rust-verify-run` lanes)
 */
import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { StringDecoder } from "node:string_decoder";
import { pathToFileURL } from "node:url";

/** cargo's exit code for "a test failed" and for "did not compile". */
const CARGO_FAILURE = 101;
/** The exit code tdd-guardian reads as a test failure. */
const TEST_FAILURE = 1;
const EX_USAGE = 64;
const EX_SPAWN_FAILED = 127;
const SIGNAL_EXIT_BASE = 128;
const FORWARDED_SIGNALS = /** @type {const} */ (["SIGINT", "SIGTERM", "SIGHUP"]);
const USAGE = "usage: node scripts/cargo-test-lane.mjs <command> [args...]  (e.g. cargo test --manifest-path …)\n";

const FAILED_SUMMARY = /^test result: FAILED\./;
// biome-ignore lint/suspicious/noControlCharactersInRegex: stripping ANSI SGR is the point
const SGR = /\x1b\[[0-9;]*m/g;

/**
 * Map cargo's outcome to the lane's outcome.
 * @param {{ code: number | null, signal: string | null, sawFailedSummary: boolean }} outcome
 * @returns {{ exit: number } | { signal: string }} `{signal}` whenever the child died by a
 *   signal; otherwise the code, except 101 with a FAILED summary seen → 1.
 */
export function classifyCargoExit({ code, signal, sawFailedSummary }) {
  if (signal) return { signal };
  return { exit: code === CARGO_FAILURE && sawFailedSummary ? TEST_FAILURE : /** @type {number} */ (code) };
}

/** @param {string} line */
function isFailedSummary(line) {
  return FAILED_SUMMARY.test(line.replace(SGR, "").replace(/\r$/, ""));
}

/**
 * A line-buffered detector for cargo's `test result: FAILED.` summary.
 * Chunks may split lines anywhere; only complete lines are judged, with ANSI
 * SGR sequences and one trailing `\r` removed, anchored at the line start.
 * Once true it stays true; `seen()` has no side effect.
 * @returns {{ push(chunk: string): void, seen(): boolean }}
 */
export function createFailedSummaryDetector() {
  let pending = "";
  let found = false;
  return {
    push(chunk) {
      if (found) return;
      pending += chunk;
      const lines = pending.split("\n");
      pending = /** @type {string} */ (lines.pop());
      found = lines.some(isFailedSummary);
    },
    seen: () => found,
  };
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

/** @param {string[]} argv the command to run and its arguments */
function main(argv) {
  if (argv.length === 0) {
    process.stderr.write(USAGE);
    process.exitCode = EX_USAGE;
    return;
  }
  const [cmd, ...args] = argv;
  const child = spawn(cmd, args, { stdio: ["inherit", "pipe", "pipe"] });
  const stdoutDetector = createFailedSummaryDetector();
  const stderrDetector = createFailedSummaryDetector();
  pipeThrough(/** @type {import("node:stream").Readable} */ (child.stdout), process.stdout, stdoutDetector);
  pipeThrough(/** @type {import("node:stream").Readable} */ (child.stderr), process.stderr, stderrDetector);

  const forwarders = FORWARDED_SIGNALS.map((sig) => /** @type {const} */ ([sig, () => child.kill(sig)]));
  for (const [sig, handler] of forwarders) process.on(sig, handler);
  let settled = false;
  const settle = () => {
    settled = true;
    for (const [sig, handler] of forwarders) process.off(sig, handler);
  };

  child.on("error", (error) => {
    if (settled || child.pid !== undefined) return;
    settle();
    process.stderr.write(`${cmd}: ${error.message}\n`);
    process.exitCode = EX_SPAWN_FAILED;
  });
  child.on("close", (code, signal) => {
    if (settled) return;
    settle();
    const sawFailedSummary = stdoutDetector.seen() || stderrDetector.seen();
    const result = classifyCargoExit({ code, signal, sawFailedSummary });
    if ("exit" in result) {
      process.exitCode = result.exit;
      return;
    }
    afterDrain(() => reraise(result.signal));
  });
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  main(process.argv.slice(2));
}
