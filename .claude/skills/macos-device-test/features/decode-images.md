# Decode real images

Picsee shows ordinary formats with correct colour, orientation and transparency, keeps the window responsive
while a large image decodes, and shows a recoverable error for a broken file instead of the previous image.

## Sub-features

- `FMT-01` JPEG, PNG, HEIC and TIFF from S1 show correct colour, orientation and transparency.
- `VIEW-06` all eight EXIF orientations show upright.
- `VIEW-07` transparent areas follow the background setting and are never black.
- `VIEW-08` a 48MP image loads without freezing the window; a preview appears, then sharpens.

## How to get to it (user POV)

- Open each fixture from Finder (or by `open -a` with the file).
- While the 48MP image loads, drag the window and open a menu.

## Driving it with computer use

Preconditions:

- Fixtures: S1's four-format set, the eight orientation images, the alpha-gradient PNG, and S3's 48MP image
  (real photo content, not a flat synthetic image).
- For VIEW-08 timing on the baseline, the Mac mini.

- **Formats.** Open the JPEG, PNG, HEIC and TIFF fixtures in turn. Each shows its known colours and upright
  orientation; the PNG's transparent area isn't black.
- **Orientation.** Open orientation images 1 to 8. Every one shows its arrow pointing up and `TOP` readable.
- **Transparency.** Open the alpha-gradient PNG. The gradient blends into the background setting, with no black
  band.
- **Large image.** Open the 48MP image and, at once, drag the window and open a menu. Both respond while the
  image is loading. A lower-resolution preview appears first, then the image sharpens.
- **Proof.** `FMT-01-<format>.png`, `VIEW-06-orientation-<n>.png`, `VIEW-07-alpha.png`,
  `VIEW-08-during-load.png`, plus the decode timing lines from `app.log`.

## Gotchas

- Flat synthetic images decode far faster than photos; never use them for VIEW-08 or timing numbers.
- "Responsive" here is observed behaviour, not a measurement. Plan §10 timings come from signposts with ≥30
  samples, recorded separately.
- A broken file is covered by `OPEN-05`, which is P1; P0 only checks that it fails cleanly in the unit seam.
