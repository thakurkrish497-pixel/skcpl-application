import contextlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release_manifest', Path(__file__).with_name('release_manifest.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

class ReleaseManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'pubspec.yaml').write_text('version: 1.0.1+2\n')
        (self.root / 'pubspec.lock').write_text('packages: {}\n')
        (self.root / 'lib').mkdir()
        (self.root / 'lib/main.dart').write_text('void main() {}\n')
        (self.root / 'assets').mkdir()
        self.dist = self.root / 'dist'
        self.dist.mkdir()
        self.root_patch = patch.object(release, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.git_patch = patch.object(release.subprocess, 'check_output', return_value='fixture-commit\n')
        self.git_patch.start()
        self.addCleanup(self.git_patch.stop)
        for platform, name in release.EXPECTED.items():
            artifact = self.dist / name
            artifact.write_bytes(b'fixture binary ' + platform.encode())
            release.create(platform, artifact)

    def combine(self):
        with contextlib.redirect_stdout(None):
            release.combine(self.dist)

    def test_complete_release_contains_all_three_platforms(self):
        self.combine()
        result = json.loads((self.dist / 'release-manifest.json').read_text())
        self.assertEqual(len(result['artifacts']), 3)
        self.assertEqual(result['build_number'], 2)
        self.assertEqual(len((self.dist / 'SHA256SUMS.txt').read_text().splitlines()), 3)

    def test_missing_platform_prevents_complete_manifest(self):
        (self.dist / 'macos-universal.json').unlink()
        with self.assertRaises(FileNotFoundError): self.combine()
        self.assertFalse((self.dist / 'release-manifest.json').exists())

    def test_mixed_versions_are_rejected(self):
        path = self.dist / 'windows-x64.json'
        data = json.loads(path.read_text()); data['version'] = '0.9.0'
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'same source and version'): self.combine()

    def test_mixed_shared_sources_are_rejected(self):
        path = self.dist / 'windows-x64.json'
        data = json.loads(path.read_text()); data['shared_source_sha256'] = 'different'
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'same source and version'): self.combine()

    def test_tampered_binary_is_rejected(self):
        (self.dist / 'SKCPL-Android.apk').write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'Artifact verification failed'): self.combine()

    def test_line_endings_do_not_change_shared_source_identity(self):
        original = release.shared_source_hash()
        (self.root / 'lib/main.dart').write_bytes(b'void main() {}\r\n')
        self.assertEqual(original, release.shared_source_hash())

if __name__ == '__main__': unittest.main()
