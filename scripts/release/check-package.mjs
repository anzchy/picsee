#!/usr/bin/env node
/**
 * Check a built Picsee.app for content that must never ship (DIST-03, spec #212 story 34).
 *
 *   node scripts/release/check-package.mjs <Picsee.app> [--require-sparkle-licence]
 *        [--expect-version 0.0.1] [--expect-build 312]
 *
 * Fails, listing every offending path, on research or prototype material, credentials, private photos,
 * stray scripts and documents, and build paths baked into any file. Also checks the Sparkle keys in
 * the shipped Info.plist and, in release mode, that Sparkle's full licence is bundled (#220 M2).
 */
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, readlinkSync, statSync } from "node:fs";
import { dirname, isAbsolute, join, normalize, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

export const SPARKLE_LICENCE_PATH = "Contents/Resources/ThirdPartyNotices/Sparkle-2.10.0-LICENSE.txt";
const SAMPLE_BUNDLE = "Contents/Resources/PicseeKit_PicseeMacUI.bundle/Contents/Resources/";
const SAMPLES = new Set(["alley", "gate", "hillside", "lakehouse", "lakeside", "temple"].map((name) => `${name}.jpg`));
const SPARKLE = "Contents/Frameworks/Sparkle.framework/";
const FEED = "https://raw.githubusercontent.com/anzchy/picsee/main/appcast.xml";

const FORBIDDEN_DIRECTORIES = new Map([
  ["evidence", "Picview research evidence"], ["docs", "repository documentation"], ["design", "design material"],
  ["TestAssets", "test assets"], ["node_modules", "npm packages"], [".stitch", "Stitch workspace"],
  [".stitch-cli", "Stitch credentials"], [".rea-cache", "REA cache"], [".npm", "npm cache"], [".git", "git metadata"],
  ["qa", "QA captures"], ["states", "prototype state pages"],
]);
const FORBIDDEN_NAMES = [
  [/^\.DS_Store$/, "Finder metadata"], [/^\.env(\..*)?$/, "environment file"],
  [/^(strings\.txt|deep-.*\.(txt|json))$/, "reverse-engineering dump"], [/^PICVIEW_/i, "Picview research"],
  [/^(analyze|deepen)_picview\.py$/, "research script"], [/private[-_]?key/i, "private key"],
  [/^(id_rsa|id_ed25519)(\.pub)?$/, "SSH key"],
];
const FORBIDDEN_EXTENSIONS = new Map([
  ["p12", "certificate bundle"], ["p8", "API private key"], ["pem", "key or certificate"], ["key", "private key"],
  ["mobileprovision", "provisioning profile"], ["html", "HTML page"], ["htm", "HTML page"], ["css", "stylesheet"],
  ["js", "script"], ["mjs", "script"], ["cjs", "script"], ["ts", "script"], ["py", "script"], ["sh", "script"],
  ["md", "document"], ["txt", "text file"], ["json", "data file"], ["zip", "archive"],
  ["jpg", "photo"], ["jpeg", "photo"], ["png", "image"], ["heic", "photo"], ["heif", "photo"], ["tif", "image"],
  ["tiff", "image"], ["gif", "image"], ["webp", "image"], ["dng", "raw photo"], ["raw", "raw photo"],
]);
const DEVELOPER_PATHS = [/\/Users\/[^/\0]+\//, /\/home\/[^/\0]+\//, /\/private\/var\/folders\//];

/** Returns why a bundle-relative path must not ship, or null when it may. */
export function classifyPath(relativePath) {
  const parts = relativePath.split("/");
  const name = parts[parts.length - 1];
  for (const part of parts.slice(0, -1)) {
    if (FORBIDDEN_DIRECTORIES.has(part)) return `${FORBIDDEN_DIRECTORIES.get(part)} (${part}/)`;
  }
  for (const [pattern, reason] of FORBIDDEN_NAMES) if (pattern.test(name)) return reason;
  // Allowed exceptions: the six B4 sample photos and their provenance, Sparkle's own stylesheet, its licence.
  if (relativePath.startsWith(SAMPLE_BUNDLE) && !relativePath.slice(SAMPLE_BUNDLE.length).includes("/") &&
      (SAMPLES.has(name) || name === "PROVENANCE.md")) return null;
  if (relativePath === SPARKLE_LICENCE_PATH) return null;
  if (relativePath.startsWith(SPARKLE) && name.endsWith(".css")) return null;
  const extension = name.includes(".") ? name.split(".").pop().toLowerCase() : "";
  if (FORBIDDEN_EXTENSIONS.has(extension)) return FORBIDDEN_EXTENSIONS.get(extension);
  return null;
}

function walk(root, directory, files, links) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    const name = relative(root, path).split(sep).join("/");
    if (entry.isSymbolicLink()) links.push(name);
    else if (entry.isDirectory()) walk(root, path, files, links);
    else files.push(name);
  }
  return files;
}

/** Framework symlinks stay relative and inside the bundle; the files they reach are checked on their own. */
function linkProblem(root, link) {
  const target = readlinkSync(join(root, link));
  const resolved = normalize(join(dirname(link), target));
  if (isAbsolute(target) || resolved === ".." || resolved.startsWith("../")) return `symlink to ${target} points outside the bundle`;
  return null;
}

/** Every offending path with its reason; an empty list means the bundle may ship. */
export function checkPackage(root, { requireSparkleLicence = false } = {}) {
  let isDirectory = false;
  try { isDirectory = statSync(root).isDirectory(); } catch { isDirectory = false; }
  if (!isDirectory) throw new Error(`${root} is not a directory`);
  const problems = [];
  const links = [];
  const files = walk(root, root, [], links).sort();
  for (const link of links.sort()) {
    const reason = classifyPath(link) ?? linkProblem(root, link);
    if (reason) problems.push({ path: link, reason });
  }
  for (const path of files) {
    const reason = classifyPath(path);
    if (reason) { problems.push({ path, reason }); continue; }
    const text = readFileSync(join(root, path)).toString("latin1");
    const leak = DEVELOPER_PATHS.map((pattern) => pattern.exec(text)).find(Boolean);
    if (leak) problems.push({ path, reason: `developer path ${leak[0]}…` });
  }
  if (requireSparkleLicence) {
    if (!files.includes(SPARKLE_LICENCE_PATH)) {
      problems.push({ path: SPARKLE_LICENCE_PATH, reason: "Sparkle 2.10.0 licence missing" });
    } else {
      const licence = readFileSync(join(root, SPARKLE_LICENCE_PATH), "utf8");
      if (!licence.startsWith("Copyright (c) 2006-2013 Andy Matuschak.") || !licence.includes("EXTERNAL LICENSES")) {
        problems.push({ path: SPARKLE_LICENCE_PATH, reason: "not Sparkle's full LICENSE with its EXTERNAL LICENSES notices" });
      }
    }
  }
  return problems;
}

/** Sparkle and version keys of the shipped Info.plist (spec #212 story 7; ADR-015). */
export function checkInfo(info, { version, build } = {}) {
  const problems = [];
  if ("SUEnableAutomaticChecks" in info) problems.push("SUEnableAutomaticChecks must stay unset so Sparkle asks on the second launch");
  if (info.SUEnableSystemProfiling !== false) problems.push("SUEnableSystemProfiling must be Boolean false");
  if (info.SUEnableInstallerLauncherService !== true) problems.push("SUEnableInstallerLauncherService must be Boolean true");
  if ("SUEnableDownloaderService" in info) problems.push("SUEnableDownloaderService must stay unset (network.client is granted)");
  if (info.SUFeedURL !== FEED) problems.push(`SUFeedURL must be ${FEED}`);
  const key = typeof info.SUPublicEDKey === "string" ? Buffer.from(info.SUPublicEDKey, "base64") : Buffer.alloc(0);
  if (key.length !== 32 || key.toString("base64") !== info.SUPublicEDKey) problems.push("SUPublicEDKey must be a base64 Ed25519 public key");
  if (version !== undefined && info.CFBundleShortVersionString !== version) {
    problems.push(`CFBundleShortVersionString is ${info.CFBundleShortVersionString}, expected ${version}`);
  }
  if (build !== undefined && info.CFBundleVersion !== build) problems.push(`CFBundleVersion is ${info.CFBundleVersion}, expected ${build}`);
  return problems;
}

function main(argv) {
  const app = argv[0];
  const option = (name) => { const index = argv.indexOf(name); return index >= 0 ? argv[index + 1] : undefined; };
  if (!app || app.startsWith("--")) {
    process.stderr.write("usage: check-package.mjs <Picsee.app> [--require-sparkle-licence] [--expect-version V] [--expect-build N]\n");
    return 2;
  }
  const problems = checkPackage(app, { requireSparkleLicence: argv.includes("--require-sparkle-licence") })
    .map(({ path, reason }) => `${path}: ${reason}`);
  const info = JSON.parse(execFileSync("/usr/bin/plutil", ["-convert", "json", "-o", "-", join(app, "Contents/Info.plist")], { encoding: "utf8" }));
  problems.push(...checkInfo(info, { version: option("--expect-version"), build: option("--expect-build") })
    .map((problem) => `Contents/Info.plist: ${problem}`));
  for (const problem of problems) process.stderr.write(`FAIL ${problem}\n`);
  if (problems.length) return 1;
  process.stdout.write(`PASS package contents of ${app}\n`);
  return 0;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main(process.argv.slice(2));
}
