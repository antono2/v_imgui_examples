"""Regression checks for downloaded archive integrity."""
import hashlib
from pathlib import Path
import tempfile
import unittest
import zipfile

from test_release_package import extract, verify_checksum


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



if __name__ == '__main__':
    unittest.main()
