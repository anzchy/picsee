# P0-07 reproducible image fixtures

These are test data, not App resources. P0-07 has no user-visible ledger row. Nothing here is wired into a
Swift/App target. Python ≥3.9 and its standard library generate all synthetic files; no Pillow, host fonts,
platform encoder, network or clock is involved. The fixed 5×7 glyphs are authored in the generator.
Generated fixtures are dedicated to CC0-1.0. No Git LFS is used in this repository.

## Three tiers

| Tier | Location | Content |
|---|---|---|
| ① | committed `TestAssets/synthetic/` | 14 small self-verifying files; byte sizes and SHA-256 in manifest |
| ② | `~/.picsee/testassets/generated/` | S2: 5,000 mixed PNG/TIFF files, 50 groups, nested directories and repeated basenames; S3: valid 8,000×6,000 (48MP) and 10,000×10,000 (100MP) noise PNGs |
| ③ | `~/.picsee/testassets/photos/` | CC0 real-scene Nikon Z8 SDR JPEG and HEIC, both with EXIF; immutable source URLs, bytes, SHA-256 and licence evidence in manifest |

The checkerboard path and bytes, and the coordinate-grid path and bytes, were landed first for #7. They are
1024×768 and 1280×960 respectively. Each grid cell is labelled by its top-left **image-pixel** coordinates,
with major lines/labels every 128 pixels and minor lines every 32 pixels. Labels remain readable at 1:1.
Do not rescale these images before an actual-pixels check.

The eight orientation files are TIFF with the EXIF/TIFF Orientation tag (0x0112), ExifVersion and an Exif
IFD. The stored pixel data is inversely rotated/mirrored for each tag so a reader honoring orientation
shows the same upright arrow, `TOP`, left `L` and right `R`. Stored sizes are 128×96 for 1–4, 96×128 for
5–8; displayed size is always 128×96. This explicitly covers mirrored cases too. These are not JPEG files.
The PNG alpha ramp has x=0 transparent and x=255 opaque; RGB stays constant. Bad fixtures are intentionally
invalid: one truncated PNG, one non-image payload and a header claiming 2147483647² pixels with no image
payload. The header fixture must never be allocated at its declared size. Corrupt dimensions are unknown
(`null`), not invented; truncated/oversize dimensions describe header claims, not decoded buffers.

**Flat synthetic images must never be used for performance numbers.** All generated assets here (including
white-noise S3 and tiny S2 files) are correctness, sorting/cancellation or allocation stress data, **not** a
representative photo performance baseline. Use tier-③ real photographs, or a separately justified
photo-noise corpus, for measurements; label the content and cache state. There are no performance results
in P0-07. In particular, the tiny S2 corpus proves enumeration topology, not real-photo decode throughput.

## Commands

```sh
python3 scripts/testassets/generate.py --output TestAssets
python3 scripts/testassets/check.py
scripts/heavy-lock.sh python3 scripts/testassets/determinism.py --tier all
scripts/heavy-lock.sh python3 scripts/testassets/generate.py --tier bulk --output ~/.picsee/testassets/generated
scripts/heavy-lock.sh python3 scripts/testassets/generate.py --tier large --output ~/.picsee/testassets/generated
python3 scripts/testassets/download.py
python3 scripts/testassets/check.py --external --native
python3 scripts/testassets/check_lock.py
```

`determinism.py` defaults to the small tier for a cheap CI-ready check; `--tier all` independently creates
all 5,016 synthetic fixtures twice under the external root. It uses system `shasum -a 256`, compares sorted
inventories, prints the 14 committed hashes plus an inventory digest, and retains both inventories and
outputs outside the repo. Bulk/large generation refuses any output inside the repository.

`check.py` always validates all 5,018 manifest entries and generated recipe coverage. By default it hashes
the 14 committed files. `--external` also requires/hashes all external files. `--native` independently
checks small valid assets and real-photo metadata with macOS ImageIO (JXA), including identical upright
rendered pixels for all eight EXIF orientations; all platforms can run the
stdlib header/hash check. The intentional bad/oversize files are never decoded by this check.
`--small-root`, `--generated-root` and `--external-root` allow scratch copies for checks. Unexpected tier-①
files, missing entries, recipe drift, wrong dimensions, wrong sizes and wrong hashes fail closed.

`download.py` uses pinned HTTPS media URLs and checks size/SHA-256 **before** atomic publication. It never
accepts a Git LFS pointer as the photo. Its sources happen to be stored with LFS upstream; downloading
verified raw media bytes requires no LFS tooling or LFS tracking here. Existing correct files are cached;
a mismatched existing file causes refusal. `--output` must be outside the repo. No personal photos are used.

`catalog.py` is an explicit maintenance tool, not a verification step: after reviewing a generator/source
change, generate the external assets and download the approved source bytes, then rebuild the manifest.
It records each synthetic recipe and the generator source hash; do not run it merely to bless a failed
check. Byte identity is proven by the independent regeneration check, not by the catalog authoring pass.

## Provenance and remaining coverage

Both real-photo files come from aaron-rust's hdr-sample-images at commit
`df0d5df406ad0dbe2124d6f2a3700fe73dd3ead7`, with per-file pinned URLs in `manifest.json`.
The author's [README](https://github.com/aaron-rust/hdr-sample-images/blob/df0d5df406ad0dbe2124d6f2a3700fe73dd3ead7/README.md)
identifies Nikon Z8 capture and explicitly dedicates all image files to CC0; the repository's
[licence](https://github.com/aaron-rust/hdr-sample-images/blob/df0d5df406ad0dbe2124d6f2a3700fe73dd3ead7/LICENSE)
contains CC0-1.0. They are 8256×5504 (45.4MP), not part of a completed 50-photo, 1–12MP S1 baseline.

The plan's S1–S6 table is a coverage roadmap, not a claim that this asset pack completes every scenario.
Manifest `gaps` records the incomplete S1 corpus and deferred S4 RAW/GIF/PDF sources. S5 filesystem
replacement/symlink/permissions/unmount and S6 multiwindow/pin topology must be constructed by future
runtime recipes. P0-07 does not measure performance, implement those behaviors or create XCUITest targets.
