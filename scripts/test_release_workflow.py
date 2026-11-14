import base64
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent

class SigningWorkflowTests(unittest.TestCase):
    def signing_script(self):
        source = (ROOT / '.github/workflows/build_releases.yml').read_text()
        marker = "          python3 - <<'PY'\n"
        start = source.index(marker) + len(marker)
        end = source.index('\n          PY', start)
        return compile('\n'.join(line[10:] for line in source[start:end].splitlines()), '<workflow signing step>', 'exec')

    def test_signing_properties_use_real_lines_and_escape_secret_characters(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'android/app').mkdir(parents=True)
            previous = Path.cwd()
            try:
                os.chdir(root)
                with patch.dict(os.environ, {
                    'ANDROID_KEYSTORE_BASE64': base64.b64encode(b'fixture-keystore').decode(),
                    'ANDROID_KEYSTORE_PASSWORD': 'fixture\\secret\nsecond line',
                    'ANDROID_KEY_PASSWORD': 'fixture password',
                    'ANDROID_KEY_ALIAS': 'upload',
                }, clear=True):
                    exec(self.signing_script(), {})
                self.assertEqual((root/'android/app/upload-keystore.jks').read_bytes(), b'fixture-keystore')
                text = (root/'android/key.properties').read_text()
                self.assertEqual(len(text.splitlines()), 4)
                self.assertTrue(text.endswith('\n'))
                self.assertIn('storePassword=fixture\\\\secret\\nsecond\\ line\n', text)
                self.assertIn('keyAlias=upload\n', text)
            finally: os.chdir(previous)

    def test_missing_signing_secrets_fail_without_creating_files(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(SystemExit, 'Configure GitHub Actions signing secrets'):
                exec(self.signing_script(), {})

if __name__ == '__main__': unittest.main()
