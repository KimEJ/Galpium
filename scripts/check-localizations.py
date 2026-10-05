#!/usr/bin/env python3
"""Check source localization coverage using macOS's native strings-file parser."""
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tables = {}
for language in ("en", "ko", "ja"):
    path = root / "Sources/GalpiumCore/Resources" / f"{language}.lproj/Localizable.strings"
    tables[language] = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
keys = set()
for source in (root / "Sources").rglob("*.swift"):
    for literal in re.findall(r'localized\(("(?:[^"\\]|\\.)*")', source.read_text()):
        keys.add(json.loads(literal))
for language, table in tables.items():
    assert keys <= table.keys(), f"{language}: missing keys {keys - table.keys()}"
    assert table.keys() == tables["en"].keys(), f"{language}: mismatched keys"
    for key, value in table.items():
        assert value and re.findall(r"%(@|ld)", key) == re.findall(r"%(@|ld)", value), (language, key)
print(f"PASS: {len(keys)} localized source keys covered in Korean, English and Japanese")
