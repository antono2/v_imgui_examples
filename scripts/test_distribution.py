"""Regression checks for downloaded archive integrity and dependency upgrades."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
import zipfile

from compatibility import resolve
from test_release_package import extract, verify_checksum, runtime_environment


class DistributionTests(unittest.TestCase):
    def test_modified_download_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'release.zip'
            archive.write_bytes(b'original release')
            checksums = Path(directory) / 'SHA256SUMS'
            checksums.write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + '  release.zip\n')
            verify_checksum(archive, checksums)
            archive.write_bytes(b'corrupt release')
            with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
                verify_checksum(archive, checksums)

    def test_download_without_unique_checksum_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'release.zip'
            archive.write_bytes(b'release')
            checksums = Path(directory) / 'SHA256SUMS'
            checksums.write_text('0' * 64 + '  another-release.zip\n')
            with self.assertRaisesRegex(ValueError, 'exactly one'):
                verify_checksum(archive, checksums)

    def test_archive_cannot_escape_extraction_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'release.zip'
            with zipfile.ZipFile(archive, 'w') as package:
                package.writestr('../outside.txt', 'bad')
            with self.assertRaisesRegex(ValueError, 'Unsafe archive path'):
                extract(archive, Path(directory) / 'extracted')
            self.assertFalse((Path(directory) / 'outside.txt').exists())

    def test_dependency_upgrade_requires_vmod_agreement(self):
        source = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for filename in ['v.mod', 'compatibility.json']:
                shutil.copyfile(source / filename, root / filename)
            manifest = json.loads((root / 'compatibility.json').read_text())
            name = next(iter(manifest['modules']))
            # Choose a direct dependency rather than an arbitrary transitive one.
            import re
            name = re.search(r"'antono2\.([a-z0-9_]+)@", (root / 'v.mod').read_text())[1]
            manifest['modules'][name] = 'v99.0.0'
            (root / 'compatibility.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'disagree'):
                resolve(root, 'windows')

    def test_platform_and_variant_pins_resolve(self):
        root = Path(__file__).resolve().parents[1]
        manifest = json.loads((root / 'compatibility.json').read_text())
        self.assertEqual(resolve(root, 'windows')['vc'], manifest['vc'])
        self.assertEqual(resolve(root, 'linux')['vc'], manifest.get('linux_vc', manifest['vc']))
        if 'imgui_standard' in manifest:
            self.assertEqual(resolve(root, 'windows', 'standard')['module_imgui'], manifest['imgui_standard'])
            self.assertEqual(resolve(root, 'linux', compiler='v3')['v'], manifest['v3_v'])

    def test_standard_can_advance_without_changing_docking(self):
        source = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copyfile(source / 'v.mod', root / 'v.mod')
            manifest = json.loads((source / 'compatibility.json').read_text())
            manifest['imgui_standard'] = 'v99.0.0-standard'
            (root / 'compatibility.json').write_text(json.dumps(manifest))
            self.assertEqual(resolve(root, 'linux', 'standard')['module_imgui'], 'v99.0.0-standard')
            self.assertEqual(resolve(root, 'linux')['module_imgui'], manifest['modules']['imgui'])
            manifest['imgui_standard'] = 'master'
            (root / 'compatibility.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'exact standard release'):
                resolve(root, 'linux', 'standard')


if __name__ == '__main__':
    unittest.main()
