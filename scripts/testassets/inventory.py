"""Canonical sorted system-shasum inventories, relative to a corpus root."""

import hashlib
from pathlib import Path
import subprocess


def inventory(folder):
    files = sorted(
        p for p in folder.rglob("*") if p.is_file() and p.name != ".DS_Store"
    )
    result = {}
    for offset in range(0, len(files), 200):
        lines = subprocess.check_output(
            ["/usr/bin/shasum", "-a", "256", *map(str, files[offset : offset + 200])],
            text=True,
        ).splitlines()
        for line in lines:
            digest, path = line.split(maxsplit=1)
            result[str(Path(path).relative_to(folder))] = digest
    return result


def inventory_text(records):
    return "".join(f"{sha}  {path}\n" for path, sha in sorted(records.items()))


def inventory_digest(records):
    return hashlib.sha256(inventory_text(records).encode("utf-8")).hexdigest()
