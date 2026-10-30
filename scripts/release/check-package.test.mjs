import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { checkInfo, checkPackage, classifyPath, SPARKLE_LICENCE_PATH } from "./check-package.mjs";

const samples = ["alley", "gate", "hillside", "lakehouse", "lakeside", "temple"];
const bundle = "Contents/Resources/PicseeKit_PicseeMacUI.bundle/Contents/Resources";
const sparkleLicence = "Copyright (c) 2006-2013 Andy Matuschak.\nPermission is hereby granted\nEXTERNAL LICENSES\nbsdiff\n";

/** A clean release-shaped bundle: what the real build plus the workflow's licence copy produce. */
function cleanTree() {
  return {
    "Contents/Info.plist": "<plist/>",
    "Contents/PkgInfo": "APPL????",
    "Contents/MacOS/Picsee": "\u0000binary",
    "Contents/Resources/AppIcon.icns": "icns",
    "Contents/Resources/Assets.car": "car",
    "Contents/Resources/en.lproj/Localizable.strings": "\"a\" = \"b\";",
    "Contents/Resources/zh-Hans.lproj/Localizable.strings": "\"a\" = \"乙\";",
    "Contents/Resources/en.lproj/Localizable.stringsdict": "<plist/>",
    "Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle": "bin",
    "Contents/Frameworks/Sparkle.framework/Versions/B/Resources/ReleaseNotesColorStyle.css": "body{}",
    "Contents/Frameworks/Sparkle.framework/Versions/B/Resources/SUUpdateAlert.nib": "nib",
    "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer": "bin",
    "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater": "bin",
    "Contents/_CodeSignature/CodeResources": "<plist/>",
    [`${bundle}/../Info.plist`]: "<plist/>",
    ...Object.fromEntries(samples.map((name) => [`${bundle}/${name}.jpg`, "jpeg"])),
    [`${bundle}/PROVENANCE.md`]: "Unsplash",
    [SPARKLE_LICENCE_PATH]: sparkleLicence,
  };
}

function materialise(tree) {
  const root = mkdtempSync(join(tmpdir(), "picsee-package-")) + "/Picsee.app";
  for (const [path, content] of Object.entries(tree)) {
    const file = join(root, path);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, content);
  }
  return root;
}

function withTree(tree, body) {
  const root = materialise(tree);
  try { return body(root); } finally { rmSync(dirname(root), { recursive: true, force: true }); }
}

test("a clean release bundle passes, including the B4 samples, Sparkle and its licence", () => {
  withTree(cleanTree(), (root) => assert.deepEqual(checkPackage(root, { requireSparkleLicence: true }), []));
});

test("every forbidden path is reported, each by its own path", () => {
  const forbidden = [
    "Contents/Resources/evidence/strings.txt",
    "Contents/Resources/docs/PICSEE_ARCHITECTURE.md",
    "Contents/Resources/design/DESIGN.md",
    "Contents/Resources/TestAssets/synthetic/landscape-3x2.png",
    "Contents/Resources/node_modules/rea-agents/package.json",
    "Contents/Resources/.stitch/generated/a.png",
    "Contents/Resources/states/settings.html",
    "Contents/Resources/prototype.css",
    "Contents/Resources/Developer.p12",
    "Contents/Resources/AuthKey_ABC.p8",
    "Contents/Resources/sparkle-private-key.txt",
    "Contents/Resources/server.pem",
    "Contents/Resources/.env",
    "Contents/Resources/.env.local",
    "Contents/Resources/.DS_Store",
    "Contents/Resources/deep-dispatch.json",
    "Contents/Resources/PICVIEW_ANALYSIS.md",
    "Contents/Resources/analyze_picview.py",
    "Contents/Resources/holiday.jpg",
    "Contents/Resources/alley.jpg",
    `${bundle}/IMG_0042.HEIC`,
    "Contents/Resources/notes.md",
    "Contents/Resources/script.mjs",
  ];
  const tree = cleanTree();
  for (const path of forbidden) tree[path] = "x";
  withTree(tree, (root) => {
    const problems = checkPackage(root, { requireSparkleLicence: true });
    const reported = problems.map((problem) => problem.path).sort();
    assert.deepEqual(reported, [...forbidden].sort());
    for (const problem of problems) assert.ok(problem.reason.length > 0, problem.path);
  });
});

test("classifyPath allows only the listed exceptions", () => {
  assert.equal(classifyPath("Contents/Frameworks/Sparkle.framework/Versions/B/Resources/ReleaseNotesColorStyle.css"), null);
  assert.notEqual(classifyPath("Contents/Resources/ReleaseNotesColorStyle.css"), null, "css outside Sparkle");
  assert.equal(classifyPath(`${bundle}/PROVENANCE.md`), null);
  assert.notEqual(classifyPath("Contents/Resources/PROVENANCE.md"), null, "provenance outside the sample bundle");
  for (const name of samples) assert.equal(classifyPath(`${bundle}/${name}.jpg`), null, name);
  assert.notEqual(classifyPath(`${bundle}/alley.png`), null);
  assert.notEqual(classifyPath(`${bundle}/seventh.jpg`), null);
  assert.equal(classifyPath(SPARKLE_LICENCE_PATH), null);
  assert.notEqual(classifyPath("Contents/Resources/other-notes.txt"), null);
  assert.equal(classifyPath("Contents/Resources/zh-Hans.lproj/Localizable.strings"), null);
});

test("build paths inside any file are developer paths", () => {
  for (const leak of ["/Users/jack/Documents/mac-app/picsee/App/Access/", "/Users/runner/work/picsee/picsee/.build/x", "/home/runner/work/x", "/private/var/folders/yc/x/T/y"]) {
    const tree = cleanTree();
    tree["Contents/MacOS/Picsee"] = `\u0000\u0001prefix${leak}suffix\u0000`;
    withTree(tree, (root) => {
      const problems = checkPackage(root);
      assert.equal(problems.length, 1, leak);
      assert.equal(problems[0].path, "Contents/MacOS/Picsee");
      assert.match(problems[0].reason, /developer path/);
    });
  }
});

test("the Sparkle licence is required in release mode and must be the full file", () => {
  const missing = cleanTree();
  delete missing[SPARKLE_LICENCE_PATH];
  withTree(missing, (root) => {
    assert.deepEqual(checkPackage(root), []);
    const problems = checkPackage(root, { requireSparkleLicence: true });
    assert.deepEqual(problems.map((p) => p.path), [SPARKLE_LICENCE_PATH]);
  });
  const truncated = cleanTree();
  truncated[SPARKLE_LICENCE_PATH] = "Copyright (c) 2006-2013 Andy Matuschak.\n";
  withTree(truncated, (root) => {
    const problems = checkPackage(root, { requireSparkleLicence: true });
    assert.deepEqual(problems.map((p) => p.path), [SPARKLE_LICENCE_PATH]);
    assert.match(problems[0].reason, /EXTERNAL LICENSES/);
  });
});

test("a missing bundle root is an error, not an empty pass", () => {
  assert.throws(() => checkPackage(join(tmpdir(), "picsee-no-such-app.app")), /not a directory/);
});

const goodInfo = {
  CFBundleIdentifier: "io.github.anzchy.picsee",
  CFBundleShortVersionString: "0.0.1",
  CFBundleVersion: "312",
  SUFeedURL: "https://raw.githubusercontent.com/anzchy/picsee/main/appcast.xml",
  SUPublicEDKey: "XaqePs6p9CwP2w+sJAC+eAKcExNITNS9W54AtIZGpSs=",
  SUEnableSystemProfiling: false,
  SUEnableInstallerLauncherService: true,
};

test("checkInfo accepts the shipped Sparkle settings and expected versions", () => {
  assert.deepEqual(checkInfo(goodInfo, { version: "0.0.1", build: "312" }), []);
  assert.deepEqual(checkInfo(goodInfo, {}), []);
});

test("checkInfo rejects each changed Sparkle or version setting", () => {
  const cases = [
    [{ SUEnableAutomaticChecks: true }, /SUEnableAutomaticChecks/],
    [{ SUEnableAutomaticChecks: false }, /SUEnableAutomaticChecks/],
    [{ SUEnableSystemProfiling: true }, /SUEnableSystemProfiling/],
    [{ SUEnableSystemProfiling: "NO" }, /SUEnableSystemProfiling/],
    [{ SUEnableInstallerLauncherService: false }, /SUEnableInstallerLauncherService/],
    [{ SUEnableDownloaderService: true }, /SUEnableDownloaderService/],
    [{ SUFeedURL: "http://raw.githubusercontent.com/anzchy/picsee/main/appcast.xml" }, /SUFeedURL/],
    [{ SUPublicEDKey: "short" }, /SUPublicEDKey/],
    [{ CFBundleShortVersionString: "0.0.2" }, /CFBundleShortVersionString/],
    [{ CFBundleVersion: "1" }, /CFBundleVersion/],
  ];
  for (const [patch, pattern] of cases) {
    const problems = checkInfo({ ...goodInfo, ...patch }, { version: "0.0.1", build: "312" });
    assert.equal(problems.length, 1, JSON.stringify(patch));
    assert.match(problems[0], pattern);
  }
});

test("framework symlinks are checked as links, never read, and must stay inside the bundle", () => {
  const tree = cleanTree();
  const root = materialise(tree);
  try {
    const framework = join(root, "Contents/Frameworks/Sparkle.framework");
    symlinkSync("B", join(framework, "Versions/Current"));
    symlinkSync("Versions/Current/Sparkle", join(framework, "Sparkle"));
    symlinkSync("Versions/Current/Resources", join(framework, "Resources"));
    assert.deepEqual(checkPackage(root, { requireSparkleLicence: true }), []);
    symlinkSync("/Users/jack/Documents/secret", join(root, "Contents/Resources/escape"));
    symlinkSync("../../../outside", join(root, "Contents/Resources/climb"));
    symlinkSync("B", join(root, "Contents/Resources/notes.md"));
    const problems = checkPackage(root, { requireSparkleLicence: true });
    assert.deepEqual(problems.map((p) => p.path).sort(),
      ["Contents/Resources/climb", "Contents/Resources/escape", "Contents/Resources/notes.md"]);
    assert.match(problems.find((p) => p.path.endsWith("escape")).reason, /outside the bundle/);
  } finally { rmSync(dirname(root), { recursive: true, force: true }); }
});
