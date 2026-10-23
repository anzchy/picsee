import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const repoRoot = new URL("../../", import.meta.url).pathname;
const buildScript = join(repoRoot, "scripts/ledger/build.mjs");

const fixture = `# 功能账簿

Intro with **bold**, [plan](./plan.md), and \`a|b < &\`.

## 状态

- One
- Two with **weight**

---

## Part 1 — picsee 现在有什么

### Alpha & <Beta>

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| OPEN-01 | Open & inspect | Partial | 单元 | P1-02、P3-01 | \`Sources/A|B.swift\` | Keep <safe> & follow [guide](guide.md) |
| OPEN-02 | Empty | Absent | 无 | P7-01 | — | Nothing |

### Second

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| VIEW-01 | View | Stub | 集成 | P2-04 | \`View.swift\` | Look |

## Part 2 — Notes

A paragraph.
`;

function tempPaths() {
  const directory = mkdtempSync(join(tmpdir(), "picsee-ledger-"));
  return {
    directory,
    source: join(directory, "ledger.md"),
    output: join(directory, "ledger.html"),
  };
}

function build(source, output, ...args) {
  return spawnSync(process.execPath, [buildScript, "--source", source, "--output", output, ...args], {
    cwd: repoRoot,
    encoding: "utf8",
  });
}

test("renders ledger rows, navigation counts, attributes, and escaped inline content", () => {
  const paths = tempPaths();
  writeFileSync(paths.source, fixture);

  const result = build(paths.source, paths.output);
  assert.equal(result.status, 0, result.stderr);
  const html = readFileSync(paths.output, "utf8");

  assert.match(html, /href="#alpha-beta"[^>]*><span class="nav-name">Alpha &amp; &lt;Beta&gt;<\/span><span class="count mono">2<\/span>/);
  assert.match(html, /href="#second"[^>]*><span class="nav-name">Second<\/span><span class="count mono">1<\/span>/);
  assert.match(html, /<tr id="OPEN-01" data-state="Partial" data-phase="1" data-search="[^"]+">/);
  assert.match(html, /<tr id="OPEN-02" data-state="Absent" data-phase="7"/);
  assert.match(html, /<tr id="VIEW-01" data-state="Stub" data-phase="2"/);
  assert.match(html, /<code>Sources\/A\|B\.swift<\/code>/);
  assert.match(html, /Keep &lt;safe&gt; &amp; follow <a href="guide\.md">guide<\/a>/);
  assert.match(html, /Intro with <strong>bold<\/strong>, <a href="\.\/plan\.md">plan<\/a>, and <code>a\|b &lt; &amp;<\/code>\./);
  assert.equal((html.match(/id="OPEN-01"/g) ?? []).length, 1);
});

test("build output is byte-identical for the same input", () => {
  const paths = tempPaths();
  writeFileSync(paths.source, fixture);
  assert.equal(build(paths.source, paths.output).status, 0);
  const first = readFileSync(paths.output);
  assert.equal(build(paths.source, paths.output).status, 0);
  assert.deepEqual(readFileSync(paths.output), first);
});

test("--check passes for fresh output and fails after the Markdown changes", () => {
  const paths = tempPaths();
  writeFileSync(paths.source, fixture);
  assert.equal(build(paths.source, paths.output).status, 0);

  const fresh = build(paths.source, paths.output, "--check");
  assert.equal(fresh.status, 0, fresh.stderr);

  writeFileSync(paths.source, `${fixture}\nchanged\n`);
  const stale = build(paths.source, paths.output, "--check");
  assert.equal(stale.status, 1);
  assert.match(stale.stderr, /^feature ledger HTML is stale; run npm run ledger:build\n$/);
});

test("real ledger renders every Part 1 row ID exactly once with matching area counts", () => {
  const paths = tempPaths();
  const source = join(repoRoot, "docs/feature-ledger.md");
  execFileSync(process.execPath, [buildScript, "--source", source, "--output", paths.output], { cwd: repoRoot });
  const html = readFileSync(paths.output, "utf8");
  const markdown = readFileSync(source, "utf8");
  const part1 = markdown.match(/## Part 1[^\n]*\n([\s\S]*?)(?=\n## Part 2)/)?.[1] ?? "";
  const ids = [...part1.matchAll(/^\| ([A-Z0-9]+-\d{2}) \|/gm)].map((match) => match[1]);

  assert.ok(ids.length > 100, `expected more than 100 Part 1 rows, got ${ids.length}`);
  for (const id of ids) {
    assert.equal((html.match(new RegExp(`id="${id}"`, "g")) ?? []).length, 1, id);
  }

  const areas = new Map();
  let area = "";
  for (const line of part1.split("\n")) {
    const heading = line.match(/^### (.+)$/);
    if (heading) area = heading[1];
    if (/^\| [A-Z0-9]+-\d{2} \|/.test(line)) areas.set(area, (areas.get(area) ?? 0) + 1);
  }
  for (const [name, count] of areas) {
    const escapedName = name.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
    assert.match(html, new RegExp(`<span class="nav-name">${escapedName}</span><span class="count mono">${count}</span>`), name);
  }
});
