from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
version = json.loads((root / 'package.json').read_text())['version']
output = root / 'dist'
files = [output / f'CodexMeter-{version}-windows-x64-{kind}.exe' for kind in ['setup', 'portable']]
lines = []
for file in files:
    if file.stat().st_size < 10_000_000:
        raise RuntimeError(f'Installer missing or unexpectedly small: {file.name}')
    with file.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    lines.append(f'{digest}  {file.name}\n')
(output / 'SHA256SUMS.txt').write_text(''.join(lines), encoding='utf-8')
print('Verified both Windows installers and generated SHA-256 checksums')
