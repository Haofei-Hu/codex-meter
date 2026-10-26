#!/usr/bin/env python3
"""Exercise upgrade cleanup only inside an isolated temporary fixture."""
import plistlib, subprocess, sys, tempfile
from pathlib import Path
helper = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='codex-meter-installer-tests-', dir='/tmp') as name:
    root = Path(name)
    apps, home = root / 'Applications', root / 'home'
    (home / 'Applications').mkdir(parents=True)
    apps.mkdir()
    def bundle(path, version, identifier='local.codexquota.mac'):
        (path / 'Contents').mkdir(parents=True)
        (path / 'Contents' / 'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=identifier, CFBundleExecutable='CodexQuota', CFBundleShortVersionString=version)))
    legacy = home / 'Applications' / 'Codex Meter.app'
    older = apps / 'CodexQuota.app'
    unrelated = apps / 'Codex.app'
    newer = home / 'Applications' / 'Future Meter.app'
    bundle(legacy, '1.4.0'); bundle(older, '1.3.0'); bundle(unrelated, '1.0', 'com.openai.codex'); bundle(newer, '9.0')
    preferences = home / 'Library' / 'Preferences' / 'local.codexquota.mac.plist'
    preferences.parent.mkdir(parents=True); preferences.write_bytes(b'keep preferences')
    auth = home / '.codex' / 'auth.json'
    auth.parent.mkdir(); auth.write_bytes(b'keep login fixture')
    def run(stage, ok=True):
        result = subprocess.run([str(helper), stage, '1.5.1.1', '--test-root', name], capture_output=True, text=True)
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
    run('prepare')
    run('finish', False)
    assert legacy.exists() and older.exists()
    bundle(apps / 'Codex Meter.app', '1.5.1.1')
    run('finish')
    assert not legacy.exists() and not older.exists()
    assert unrelated.exists() and newer.exists() and (apps / 'Codex Meter.app').exists()
    assert len(list((home / '.Trash').glob('*.app'))) == 2
    assert preferences.read_bytes() == b'keep preferences' and auth.read_bytes() == b'keep login fixture'
    run('finish')
    assert len(list((home / '.Trash').glob('*.app'))) == 2
print('PASS installer: safe replacement, recoverable duplicate cleanup, missing-payload rollback guard, no downgrade, preferences/login preserved, retry safe')
