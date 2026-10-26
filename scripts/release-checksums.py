#!/usr/bin/env python3
"""Require the complete release asset set and hash the bytes published to GitHub."""
import hashlib
from pathlib import Path
import sys

root, version = Path(sys.argv[1]), sys.argv[2]
expected = {
    f"CodexMeter-{version}-universal.dmg",
    f"CodexMeter-{version}-universal.zip",
    f"CodexMeter-{version}-windows-x64-setup.exe",
    f"CodexMeter-{version}-windows-x64-portable.exe",
    f"CodexMeter-{version}-linux-x64.AppImage",
    f"CodexMeter-{version}-linux-x64.deb",
}
actual = {p.name for p in root.iterdir() if p.is_file()}
if actual != expected:
    raise SystemExit(f"Release asset mismatch. Missing: {expected - actual}; extra: {actual - expected}")
checksums = []
for name in sorted(expected):
    file = root / name
    if file.stat().st_size < 100_000:
        raise SystemExit(f"Unexpectedly small installer: {name}")
    digest = hashlib.file_digest(file.open('rb'), 'sha256').hexdigest()
    checksums.append(f"{digest}  {name}")
(root / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n')
print('\n'.join(checksums))
