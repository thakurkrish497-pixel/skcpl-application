#!/usr/bin/env python3
"""Record and verify native release files without sending application data anywhere."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
EXPECTED = {
    'android': 'SKCPL-Android.apk',
    'windows-x64': 'SKCPL-Windows-x64.zip',
    'macos-universal': 'SKCPL-macOS.zip',
}

def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()

def shared_source_hash():
    digest = hashlib.sha256()
    paths = [ROOT / 'pubspec.yaml', ROOT / 'pubspec.lock']
    for folder in ['lib', 'assets']:
        paths.extend(p for p in (ROOT / folder).rglob('*') if p.is_file() and p.name != '.DS_Store')
    for path in sorted(paths):
        contents = path.read_bytes()
        try:
            contents = contents.decode('utf-8').replace('\r\n', '\n').encode('utf-8')
        except UnicodeDecodeError:
            pass
        digest.update(path.relative_to(ROOT).as_posix().encode() + b'\0')
        digest.update(hashlib.sha256(contents).digest())
    return digest.hexdigest()

def create(platform, artifact):
    artifact = Path(artifact).resolve()
    if artifact.name != EXPECTED[platform] or not artifact.is_file():
        raise ValueError('The expected artifact filename was not found.')
    match = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$', (ROOT / 'pubspec.yaml').read_text(), re.M)
    if not match:
        raise ValueError('pubspec must have an explicit semantic version and build number.')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    data = {
        'version': match[1], 'build_number': int(match[2]),
        'source_commit': commit, 'source_worktree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
        'shared_source_sha256': shared_source_hash(),
        'platform': platform, 'filename': artifact.name,
        'bytes': artifact.stat().st_size, 'sha256': sha256(artifact),
    }
    if platform == 'macos-universal':
        data.update(signed=os.environ.get('MACOS_SIGNED') == 'true', notarized=os.environ.get('MACOS_NOTARIZED') == 'true')
    if platform == 'windows-x64':
        data['signed'] = False
    artifact.with_name(f'{platform}.json').write_text(json.dumps(data, indent=2) + '\n')

def combine(folder):
    folder = Path(folder)
    records = [json.loads((folder / f'{platform}.json').read_text()) for platform in EXPECTED]
    identities = {(r['version'], r['build_number'], r['source_commit'], r['shared_source_sha256']) for r in records}
    if len(identities) != 1:
        raise ValueError('Platform builds do not describe the same source and version.')
    for platform, record in zip(EXPECTED, records):
        if record['platform'] != platform or record['filename'] != EXPECTED[platform]:
            raise ValueError('Unexpected platform artifact.')
        artifact = folder / record['filename']
        if artifact.stat().st_size != record['bytes'] or sha256(artifact) != record['sha256']:
            raise ValueError(f'Artifact verification failed: {platform}')
    version, number, commit, source_hash = next(iter(identities))
    result = dict(version=version, build_number=number, source_commit=commit, shared_source_sha256=source_hash, artifacts=records)
    (folder / 'release-manifest.json').write_text(json.dumps(result, indent=2) + '\n')
    (folder / 'SHA256SUMS.txt').write_text(''.join(f"{r['sha256']}  {r['filename']}\n" for r in records))
    mac = next(r for r in records if r['platform'] == 'macos-universal')
    (folder / 'RELEASE_NOTES.md').write_text(
        f"SKCPL ERP {version} (build {number})\n\n"
        f"Source: {commit}\n\n"
        "Native Android APK, Windows x64 ZIP (SKCPL.exe and required DLL/data files), and universal macOS APP/ZIP.\n"
        "Includes the current sync, approval-role and responsive layout changes. No web ERP or Play Store upload.\n\n"
        "Sync pending entries before updating. Keep device application data and local drafts.\n"
        "Windows: extract the entire ZIP. Executable is not Authenticode-signed.\n"
        f"macOS: Developer ID signed: {mac['signed']}; notarized: {mac['notarized']}. "
        "Unnotarized downloads may be blocked by Gatekeeper; contact company IT for a signed release.\n\n"
        "Use SHA256SUMS.txt to verify downloads. Native permissions and operational workflows still need device acceptance testing.\n")
    print(f'v{version}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', choices=EXPECTED)
    parser.add_argument('--artifact')
    parser.add_argument('--combine')
    args = parser.parse_args()
    if args.combine:
        combine(args.combine)
    elif args.platform and args.artifact:
        create(args.platform, args.artifact)
    else:
        parser.error('Specify --combine or both --platform and --artifact.')
