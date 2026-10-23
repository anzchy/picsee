"""Regression checks for P0-07 tooling; all mutation uses disposable copies."""

import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import urllib.request
import zlib

import check
import determinism
import download
import generate


class Checks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.small = self.root / "small"
        shutil.copytree(check.ROOT / "TestAssets", self.small)
        self.manifest = json.loads((self.small / "manifest.json").read_text())

    def verify(self):
        (self.small / "manifest.json").write_text(json.dumps(self.manifest))
        args = mock.Mock(
            manifest=self.small / "manifest.json",
            small_root=self.small,
            external=False,
            native=False,
        )
        with contextlib.redirect_stdout(io.StringIO()):
            check.verify(args)

    def photo(self):
        return next(a for a in self.manifest["assets"] if a["tier"] == 3)

    def bulk_case(self):
        specs = generate.bulk_specs()[:4]
        generated = self.root / "generated"
        with contextlib.redirect_stdout(io.StringIO()):
            generate.generate(generated, specs)
        records = {
            spec["path"]: hashlib.sha256(
                (generated / spec["path"]).read_bytes()
            ).hexdigest()
            for spec in specs
        }
        canonical = "".join(
            f"{digest}  {path}\n" for path, digest in sorted(records.items())
        )
        manifest = {"bulk": copy.deepcopy(self.manifest["bulk"])}
        manifest["bulk"]["count"] = len(specs)
        manifest["bulk"]["inventory_sha256"] = hashlib.sha256(
            canonical.encode("utf-8")
        ).hexdigest()
        args = mock.Mock(external=True, generated_root=generated)
        return manifest, args, specs

    def check_bulk(self, manifest, args, specs):
        with mock.patch.object(generate, "bulk_specs", return_value=specs):
            return check.check_bulk(manifest, args)

    def download_case(
        self, data, expected_size=8, message="download exceeds expected size"
    ):
        asset = copy.deepcopy(self.photo())
        asset["byte_size"] = expected_size
        asset["sha256"] = hashlib.sha256(b"expected").hexdigest()
        response = mock.MagicMock()
        response.__enter__.return_value = response
        response.geturl.return_value = asset["url"]
        response.read.side_effect = [data, b""]
        with mock.patch.object(
            download, "load_manifest", return_value={"assets": [asset]}
        ), mock.patch.object(download, "open_https", return_value=response):
            with self.assertRaisesRegex(ValueError, message):
                download.download(self.root)
        self.assertFalse((self.root / asset["path"]).exists())
        self.assertEqual(list((self.root / "photos").iterdir()), [])

    def test_tampered_bytes(self):
        path = self.small / "synthetic/checkerboard-1px.png"
        data = bytearray(path.read_bytes())
        data[-1] ^= 1
        path.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "sha256 mismatch"):
            self.verify()

    def test_unsafe_path(self):
        self.manifest["assets"][0]["path"] = "../escape.png"
        with self.assertRaisesRegex(ValueError, "unsafe asset path"):
            self.verify()

    def test_generator_hash_drift(self):
        self.manifest["generator_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "generator source hash mismatch"):
            self.verify()

    def test_lfs_pointer(self):
        pointer = b"version https://git-lfs.github.com/spec/v1\n"
        self.download_case(pointer, len(pointer), "download size/sha256 mismatch")

    def test_oversize_download(self):
        self.download_case(b"x" * 9)

    def test_mismatched_existing_photo(self):
        asset = self.photo()
        target = self.root / asset["path"]
        target.parent.mkdir()
        target.write_bytes(b"wrong")
        with self.assertRaisesRegex(ValueError, "existing file differs"):
            download.download(self.root)
        self.assertEqual(target.read_bytes(), b"wrong")

    def test_https_redirect_rejected_before_followup(self):
        handler = download.HTTPSOnlyRedirect()
        request = urllib.request.Request("https://example.com/photo")
        with self.assertRaisesRegex(ValueError, "HTTPS redirect required"):
            handler.redirect_request(
                request, None, 302, "redirect", {}, "http://example.com/photo"
            )
        self.assertIsNotNone(
            handler.redirect_request(
                request, None, 302, "redirect", {}, "https://example.com/next"
            )
        )

    def test_finder_file_ignored(self):
        (self.small / ".DS_Store").write_bytes(b"finder")
        self.verify()

    def test_unexpected_path_named(self):
        (self.small / "surprise.png").write_bytes(b"unknown")
        with self.assertRaisesRegex(ValueError, "surprise.png"):
            self.verify()

    def test_compact_bulk_inventory(self):
        self.assertFalse(
            any(a["path"].startswith("S2/") for a in self.manifest["assets"])
        )
        self.assertEqual(len(self.manifest["bulk"]["inventory_sha256"]), 64)

    def test_bulk_inventory_baseline(self):
        manifest, args, specs = self.bulk_case()
        self.assertEqual(self.check_bulk(manifest, args, specs), len(specs))

    def test_bulk_inventory_changed_bytes(self):
        manifest, args, specs = self.bulk_case()
        target = args.generated_root / specs[0]["path"]
        data = bytearray(target.read_bytes())
        data[-1] ^= 1
        target.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "bulk inventory sha256 mismatch"):
            self.check_bulk(manifest, args, specs)

    def test_bulk_inventory_missing_path(self):
        manifest, args, specs = self.bulk_case()
        missing = specs[0]["path"]
        (args.generated_root / missing).unlink()
        with self.assertRaisesRegex(ValueError, "paths differ.*" + missing):
            self.check_bulk(manifest, args, specs)

    def test_bulk_inventory_extra_path(self):
        manifest, args, specs = self.bulk_case()
        extra = "S2/extra.png"
        (args.generated_root / extra).write_bytes(b"extra")
        with self.assertRaisesRegex(ValueError, "paths differ.*" + extra):
            self.check_bulk(manifest, args, specs)

    def test_bulk_inventory_ignores_finder_file(self):
        manifest, args, specs = self.bulk_case()
        (args.generated_root / "S2/.DS_Store").write_bytes(b"finder")
        self.assertEqual(self.check_bulk(manifest, args, specs), len(specs))

    def test_versions_report_both(self):
        self.manifest["generator_environment"] = {"python": "0.0", "zlib": "0.0"}
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            check.check_environment(self.manifest)
        self.assertIn("manifest=0.0", output.getvalue())
        self.assertIn("runtime=", output.getvalue())
        self.assertIn("Python", output.getvalue())
        self.assertIn("zlib", output.getvalue())

    def test_regenerated_small_matches_manifest(self):
        records = {
            a["path"]: a["sha256"] for a in self.manifest["assets"] if a["tier"] == 1
        }
        determinism.compare_manifest(records, self.manifest)
        records[next(iter(records))] = "0" * 64
        with self.assertRaisesRegex(ValueError, "committed manifest"):
            determinism.compare_manifest(records, self.manifest)

    def test_p1_fixture_contract(self):
        specs = {spec["path"]: spec for spec in generate.small_specs()}
        expected = {
            "synthetic/landscape-3x2.png": {
                "kind": "framed",
                "width": 600,
                "height": 400,
                "label": "LANDSCAPE",
            },
            "synthetic/portrait-2x3.png": {
                "kind": "framed",
                "width": 400,
                "height": 600,
                "label": "PORTRAIT",
            },
            "synthetic/pan-grid-4096x3072.png": {
                "kind": "grid",
                "width": 4096,
                "height": 3072,
                "spacing": 512,
            },
            "synthetic/not-an-image.jpg": {
                "kind": "not-image",
                "width": None,
                "height": None,
            },
            "synthetic/unsupported-container.zip": {
                "kind": "unsupported-container",
                "width": None,
                "height": None,
                "container": "ZIP",
            },
            "synthetic/gradient-16bit.png": {
                "kind": "gradient-16bit",
                "width": 256,
                "height": 128,
                "bit_depth": 16,
            },
        }
        for path, parameters in expected.items():
            self.assertEqual(
                {key: value for key, value in specs[path].items() if key != "path"},
                parameters,
            )
            self.assertEqual(generate.render(specs[path]), generate.render(specs[path]))

        landscape = generate.render(specs["synthetic/landscape-3x2.png"])
        portrait = generate.render(specs["synthetic/portrait-2x3.png"])
        self.assertEqual(self.png_ihdr(landscape), (600, 400, 8, 0))
        self.assertEqual(self.png_ihdr(portrait), (400, 600, 8, 0))
        for data, width, height in [(landscape, 600, 400), (portrait, 400, 600)]:
            pixels = self.png_grayscale_pixels(data, width, height, 1)
            self.assertEqual(pixels[8 * width + 8], 0, "labelled frame has a border")
            centre = (height // 2) * width + width // 2
            self.assertEqual(pixels[centre], 0, "framed fixture has a centre mark")

        invalid_jpeg = generate.render(specs["synthetic/not-an-image.jpg"])
        self.assertTrue(invalid_jpeg.startswith(b"PICSEE text fixture"))
        self.assertFalse(invalid_jpeg.startswith(b"\xff\xd8\xff"))
        unsupported = generate.render(specs["synthetic/unsupported-container.zip"])
        self.assertTrue(unsupported.startswith(b"PK\x03\x04"))
        self.assertTrue(unsupported.endswith(b"PK\x05\x06" + unsupported[-18:]))

        gradient = generate.render(specs["synthetic/gradient-16bit.png"])
        self.assertEqual(self.png_ihdr(gradient), (256, 128, 16, 0))
        samples = self.png_grayscale_pixels(gradient, 256, 128, 2)
        self.assertEqual(samples[:4], b"\x00\x00\x01\x01")
        self.assertEqual(samples[510:512], b"\xff\xff")

    @staticmethod
    def png_ihdr(data):
        return (*__import__("struct").unpack(">II", data[16:24]), data[24], data[25])

    @staticmethod
    def png_grayscale_pixels(data, width, height, bytes_per_sample):
        offset = 8
        compressed = bytearray()
        while offset < len(data):
            length = int.from_bytes(data[offset : offset + 4], "big")
            kind = data[offset + 4 : offset + 8]
            payload = data[offset + 8 : offset + 8 + length]
            if kind == b"IDAT":
                compressed.extend(payload)
            offset += 12 + length
        raw = zlib.decompress(compressed)
        row_size = width * bytes_per_sample
        rows = []
        for y in range(height):
            start = y * (row_size + 1)
            if raw[start] != 0:
                raise AssertionError("fixture must use PNG filter 0")
            rows.append(raw[start + 1 : start + 1 + row_size])
        return b"".join(rows)

    @unittest.skipUnless(sys.platform == "darwin", "requires macOS ImageIO")
    def test_native_without_external_honest_summary(self):
        result = subprocess.run(
            [
                sys.executable,
                str(check.ROOT / "scripts/testassets/check.py"),
                "--native",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("alpha and photo EXIF", result.stdout)
        self.assertIn("photo EXIF skipped", result.stdout)
        self.assertIn("truncated: partial or failed, never a crash", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
