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

import check
import determinism
import download


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
