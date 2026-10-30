import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const root = new URL("../../", import.meta.url).pathname;
const workflow = readFileSync(join(root, ".github/workflows/release.yml"), "utf8");

/** The `run: |` script of the named step, de-indented, exactly as the runner receives it. */
export function stepScript(name) {
  const lines = workflow.split("\n");
  const start = lines.findIndex((line) => line === `      - name: ${name}`);
  assert.ok(start >= 0, `no step ${name}`);
  const run = lines.findIndex((line, index) => index > start && line === "        run: |");
  assert.ok(run > start, `step ${name} has no run block`);
  const body = [];
  for (const line of lines.slice(run + 1)) {
    if (line.trim() !== "" && !line.startsWith("          ")) break;
    body.push(line.slice(10));
  }
  return body.join("\n").replace(/\s+$/, "") + "\n";
}

/** Runs a step the way GitHub's macOS runner does (bash --noprofile --norc -eo pipefail) under /bin/bash 3.2. */
export function runStep(name, { env = {}, cwd = root, fakes = {} } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "picsee-step-"));
  const bin = join(dir, "bin");
  mkdirSync(bin);
  for (const [command, script] of Object.entries(fakes)) {
    writeFileSync(join(bin, command), `#!/bin/bash\n${script}`);
    chmodSync(join(bin, command), 0o755);
  }
  const file = join(dir, "step.sh");
  writeFileSync(file, stepScript(name));
  const result = spawnSync("/bin/bash", ["--noprofile", "--norc", "-eo", "pipefail", file], {
    cwd, encoding: "utf8", env: { PATH: `${bin}:/usr/bin:/bin:/usr/sbin:/sbin`, HOME: dir, RUNNER_TEMP: dir, ...env },
  });
  return { ...result, dir, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

test("/bin/bash is the 3.2 shell the macos-26 runner has", () => {
  assert.match(execFileSync("/bin/bash", ["--version"], { encoding: "utf8" }), /version 3\.2\./);
});

for (const [tag, prerelease] of [["v0.0.1-rc.1", true], ["v0.0.1", false]]) {
  test(`the draft-release step calls gh with the full argument list for ${tag}`, () => {
    const step = runStep("Create the draft release", {
      env: { TAG: tag, VERSION: "0.0.1", BUILD: "312", SHA256: "ab".repeat(32), DMG: "/build/Picsee-0.0.1.dmg", GH_TOKEN: "token" },
      fakes: { gh: 'printf "%s\\n" "$@" > "$RUNNER_TEMP/gh-argv"\n' },
    });
    try {
      assert.equal(step.status, 0, step.stderr);
      const argv = readFileSync(join(step.dir, "gh-argv"), "utf8").trimEnd().split("\n");
      assert.deepEqual(argv, ["release", "create", tag, "/build/Picsee-0.0.1.dmg", "/build/Picsee-0.0.1.dmg.sha256",
        "--draft", "--verify-tag", "--title", `picsee 0.0.1 (${tag.slice(1)})`, "--notes-file", join(step.dir, "notes.md"),
        ...(prerelease ? ["--prerelease"] : [])]);
      const notes = readFileSync(join(step.dir, "notes.md"), "utf8");
      assert.match(notes, new RegExp(`${"ab".repeat(32)}  Picsee-0\\.0\\.1\\.dmg`));
      assert.match(notes, /build 312/);
      assert.doesNotMatch(notes, /\{\{/);
    } finally { step.cleanup(); }
  });
}

/** A repository with two commits on main and one side commit, like a tag pushed from a branch. */
function repository() {
  const dir = mkdtempSync(join(tmpdir(), "picsee-tag-"));
  const git = (...args) => execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.com", ...args],
    { cwd: dir, encoding: "utf8" }).trim();
  git("init", "-q", "-b", "main");
  writeFileSync(join(dir, "project.yml"), "targets:\n  PicseeApp:\n    settings:\n      base:\n        MARKETING_VERSION: 0.0.1\n");
  git("add", "project.yml"); git("commit", "-q", "-m", "a");
  const first = git("rev-parse", "HEAD");
  git("commit", "-q", "--allow-empty", "-m", "b");
  const second = git("rev-parse", "HEAD");
  git("update-ref", "refs/remotes/origin/main", second);
  git("switch", "-q", "-c", "side"); git("commit", "-q", "--allow-empty", "-m", "c");
  const side = git("rev-parse", "HEAD");
  git("switch", "-q", "main");
  return { dir, first, second, side };
}

test("the version step accepts a tag on main whose version matches and exports the build", () => {
  const repo = repository();
  try {
    for (const [tag, sha, build] of [["v0.0.1", repo.second, "2"], ["v0.0.1-rc.3", repo.first, "1"]]) {
      const env = join(repo.dir, `env-${tag}`);
      writeFileSync(env, "");
      const step = runStep("Check the tag against the project version", { cwd: repo.dir,
        env: { GITHUB_REF_NAME: tag, GITHUB_SHA: sha, GITHUB_ENV: env, DEVELOPMENT_TEAM: "GRT84NAK4T" } });
      try {
        assert.equal(step.status, 0, step.stderr);
        assert.deepEqual(readFileSync(env, "utf8").trim().split("\n"), [`TAG=${tag}`, "VERSION=0.0.1", `BUILD=${build}`]);
      } finally { step.cleanup(); }
    }
  } finally { rmSync(repo.dir, { recursive: true, force: true }); }
});

test("the version step fails on a mismatched or malformed tag, a commit off main, or no team", () => {
  const repo = repository();
  try {
    const cases = [
      ["v0.0.2", repo.second, "GRT84NAK4T", /does not match MARKETING_VERSION/],
      ["v0.0.1", repo.side, "GRT84NAK4T", /is not on main/],
      ["v0.0.1-rc.0", repo.second, "GRT84NAK4T", /unexpected tag/],
      ["v0.0.1-beta", repo.second, "GRT84NAK4T", /unexpected tag/],
      ["0.0.1", repo.second, "GRT84NAK4T", /unexpected tag/],
      ["v0.0.1", repo.second, "", /DEVELOPMENT_TEAM is not set/],
    ];
    for (const [tag, sha, team, message] of cases) {
      const env = join(repo.dir, "env");
      writeFileSync(env, "");
      const step = runStep("Check the tag against the project version", { cwd: repo.dir,
        env: { GITHUB_REF_NAME: tag, GITHUB_SHA: sha, GITHUB_ENV: env, DEVELOPMENT_TEAM: team } });
      try {
        assert.notEqual(step.status, 0, `${tag} ${team}`);
        assert.match(step.stdout + step.stderr, message, tag);
        assert.equal(readFileSync(env, "utf8"), "", `${tag} must export nothing`);
      } finally { step.cleanup(); }
    }
  } finally { rmSync(repo.dir, { recursive: true, force: true }); }
});
