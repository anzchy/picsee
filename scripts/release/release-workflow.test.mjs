import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const root = new URL("../../", import.meta.url);
const workflow = readFileSync(new URL(".github/workflows/release.yml", root), "utf8");
const notarize = readFileSync(new URL("scripts/release/notarize.sh", root), "utf8");
const notes = readFileSync(new URL("docs/release/notes-template.md", root), "utf8");

const SECRETS = ["DEVELOPER_ID_P12_BASE64", "DEVELOPER_ID_P12_PASSWORD", "KEYCHAIN_PASSWORD", "APPLE_ID",
  "APPLE_APP_SPECIFIC_PASSWORD", "SPARKLE_ED_PRIVATE_KEY"];

/** The release job's steps as {name, text}, in order. The workflow is ours, so a line splitter is enough. */
function steps() {
  const body = workflow.slice(workflow.indexOf("\n    steps:\n"));
  const parts = body.split(/^      - name: /m).slice(1);
  return parts.map((part) => ({ name: part.split("\n")[0].trim(), text: part }));
}
const step = (pattern) => {
  const found = steps().find((entry) => pattern.test(entry.name));
  assert.ok(found, `no step named ${pattern}`);
  return found;
};
const index = (pattern) => steps().findIndex((entry) => pattern.test(entry.name));

test("only the two v0.0.1 tag patterns trigger a release", () => {
  const on = workflow.slice(workflow.indexOf("\non:\n") + 1, workflow.indexOf("\npermissions:"));
  assert.match(on, /^on:\n  push:\n    tags:\n      - 'v0\.0\.1-rc\.\*'\n      - 'v0\.0\.1'\n$/);
});

test("permissions are only contents and pull-requests write", () => {
  const block = /\npermissions:\n((?:  .*\n)+)/.exec(workflow)?.[1];
  assert.equal(block, "  contents: write\n  pull-requests: write\n");
  assert.equal((workflow.match(/permissions:/g) ?? []).length, 1);
});

test("every action is local or pinned to a full commit SHA", () => {
  const uses = [...workflow.matchAll(/uses:\s*(\S+)/g)].map((match) => match[1]);
  assert.ok(uses.length > 0);
  for (const use of uses) assert.match(use, /^(\.\/.+|[\w.-]+\/[\w.-]+@[0-9a-f]{40})$/, use);
});

test("secrets come only from secrets.*, only through env, and never echo", () => {
  const referenced = [...workflow.matchAll(/secrets\.(\w+)/g)].map((match) => match[1]);
  assert.deepEqual([...new Set(referenced)].sort(), [...SECRETS].sort());
  for (const line of workflow.split("\n").filter((l) => l.includes("secrets."))) {
    assert.match(line, /^\s+(\w+): \$\{\{ secrets\.(\w+) \}\}$/, `secret outside an env mapping: ${line}`);
  }
  assert.doesNotMatch(workflow + notarize, /set -[a-wyz]*x|set -o xtrace|bash -x/);
  assert.match(workflow, /\$\{\{ vars\.DEVELOPMENT_TEAM \}\}/);
  for (const name of SECRETS) assert.doesNotMatch(workflow, new RegExp(`echo[^\\n]*\\$\\{?${name}`), name);
});

test("the private Sparkle key only reaches sign_update on stdin", () => {
  const sign = step(/appcast/i).text;
  assert.match(sign, /printf '%s' "\$SPARKLE_ED_PRIVATE_KEY" \| "\$SPARKLE_TOOLS\/bin\/sign_update" -p --ed-key-file - /);
  // The env mapping names it twice (`NAME: ${{ secrets.NAME }}`); the only other use is the stdin pipe.
  assert.equal((workflow.match(/SPARKLE_ED_PRIVATE_KEY/g) ?? []).length, 3, "one env mapping, one stdin pipe");
});

test("the release is a draft and nothing is published or merged", () => {
  const create = step(/draft release/i).text;
  assert.match(create, /args=\(release create "\$TAG"[^\n]*--draft/);
  assert.match(create, /^\s*gh "\$\{args\[@\]\}"$/m);
  assert.match(create, /--verify-tag/);
  assert.doesNotMatch(workflow, /--draft=false|gh release edit|gh pr merge|--publish|git push[^\n]*\bmain\b/);
  const pr = step(/appcast/i).text;
  assert.match(pr, /gh pr create --base main/);
  assert.match(pr, /git push --force-with-lease="refs\/heads\/\$BRANCH:\$REMOTE" origin "HEAD:refs\/heads\/\$BRANCH"/);
  assert.match(pr, /git push origin "HEAD:refs\/heads\/\$BRANCH"/);
  for (const push of pr.split("\n").filter((line) => line.includes("git push"))) assert.match(push, /"HEAD:refs\/heads\/\$BRANCH"$/, push);
});

test("the tag must be on main and match the project's marketing version", () => {
  const check = step(/version/i);
  assert.ok(index(/version/i) < index(/build release/i));
  assert.match(check.text, /git merge-base --is-ancestor "\$GITHUB_SHA" origin\/main/);
  assert.match(check.text, /MARKETING_VERSION/);
  assert.match(check.text, /git rev-list --count "\$GITHUB_SHA"/);
  assert.match(step(/checkout/i).text, /fetch-depth: 0/);
});

test("the Release build signs with Developer ID, hardened runtime, no injected entitlements, stripped", () => {
  const build = step(/build release/i).text;
  for (const setting of ["-configuration Release", "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO", "ENABLE_HARDENED_RUNTIME=YES",
    "DEPLOYMENT_POSTPROCESSING=YES", "STRIP_INSTALLED_PRODUCT=YES", 'CURRENT_PROJECT_VERSION="$BUILD"',
    'CODE_SIGN_IDENTITY="$IDENTITY"', 'DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"', "--timestamp"]) {
    assert.ok(build.includes(setting), setting);
  }
  assert.match(step(/certificate/i).text, /Developer ID Application/);
});

test("Sparkle's tools are the pinned 2.10.0 tarball, checked by SHA-256", () => {
  const tools = step(/sparkle tools/i).text;
  assert.match(tools, /releases\/download\/2\.10\.0\/Sparkle-2\.10\.0\.tar\.xz/);
  assert.match(tools, /c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c/);
  assert.match(tools, /shasum -a 256 --check/);
  assert.doesNotMatch(workflow, /latest/);
});

test("Sparkle's helpers are re-signed in the documented order, then the app, without --deep", () => {
  const sign = step(/re-sign/i).text;
  const order = ["XPCServices/Installer.xpc", "XPCServices/Downloader.xpc", "Versions/B/Autoupdate", "Versions/B/Updater.app",
    '"$SPARKLE"\n', '"$APP"\n'].map((needle) => sign.indexOf(needle));
  for (const position of order) assert.ok(position >= 0, sign);
  assert.deepEqual([...order].sort((a, b) => a - b), order);
  assert.match(sign, /--preserve-metadata=entitlements[^\n]*Downloader\.xpc/);
  for (const line of sign.split("\n").filter((l) => /codesign (-f|--force)/.test(l))) {
    assert.doesNotMatch(line, /--deep/);
    assert.match(line, /-o runtime --timestamp/);
  }
  assert.match(sign, /codesign --verify --deep --strict/);
  assert.ok(index(/licence/i) < index(/re-sign/i), "the licence is added before the final app signature");
});

test("entitlement and package checks run on the signed app before notarisation", () => {
  const notarise = index(/notarise the app/i);
  assert.ok(index(/re-sign/i) < index(/entitlements/i) && index(/entitlements/i) < notarise);
  assert.ok(index(/re-sign/i) < index(/package contents/i) && index(/package contents/i) < notarise);
  assert.match(step(/entitlements/i).text, /node scripts\/release\/check-entitlements\.mjs "\$APP" --configuration release/);
  assert.match(step(/package contents/i).text,
    /node scripts\/release\/check-package\.mjs "\$APP" --require-sparkle-licence --expect-version "\$VERSION" --expect-build "\$BUILD"/);
});

test("the DMG holds the stapled app and an Applications link, and is signed", () => {
  assert.ok(index(/notarise the app/i) < index(/dmg/i));
  const dmg = step(/build and sign the dmg/i).text;
  assert.match(dmg, /ln -s \/Applications/);
  assert.match(dmg, /hdiutil create /);
  assert.match(dmg, /codesign --force --sign "\$IDENTITY" --timestamp/);
});

test("notarisation uses the Apple ID contract, waits, and fails unless Accepted", () => {
  assert.match(notarize, /xcrun notarytool submit "\$1" --apple-id "\$APPLE_ID" --password "\$APPLE_APP_SPECIFIC_PASSWORD" --team-id "\$DEVELOPMENT_TEAM" --wait/);
  assert.match(notarize, /"Accepted"/);
  assert.match(notarize, /notarytool log/);
  assert.match(notarize, /^set -euo pipefail$/m);
  const app = step(/notarise the app/i).text, dmg = step(/notarise the dmg/i).text;
  for (const text of [app, dmg]) {
    assert.match(text, /scripts\/release\/notarize\.sh/);
    assert.match(text, /xcrun stapler staple/);
    assert.match(text, /xcrun stapler validate/);
  }
  assert.match(dmg, /spctl -a -t open --context context:primary-signature -v "\$DMG"/);
  assert.match(dmg, /spctl -a -vv "\$APP"/);
});

test("the release carries the DMG, its SHA-256 and notes with the privacy statement", () => {
  const create = step(/draft release/i).text;
  assert.match(create, /"\$DMG" "\$DMG\.sha256"/);
  assert.match(create, /--notes-file/);
  assert.ok(index(/checksum/i) < index(/draft release/i));
  assert.ok(index(/draft release/i) < index(/appcast/i));
  assert.match(notes, /\{\{SHA256\}\}/);
  assert.match(notes, /collects no data/);
});

test("the temporary keychain is always deleted", () => {
  const cleanup = step(/keychain/i);
  assert.equal(index(/keychain/i), steps().length - 1, "cleanup is the last step");
  assert.match(cleanup.text, /^\s+if: always\(\)$/m);
  assert.match(cleanup.text, /security delete-keychain/);
});
