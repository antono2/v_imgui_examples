"""Exercise independently versioned standard bindings with real Git fixtures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class InstalledDependencies(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'scripts').mkdir()
        shutil.copyfile(Path(__file__).with_name('check_installed_deps.vsh'),
                        self.root / 'scripts/check_installed_deps.vsh')
        (self.root / 'v.mod').write_text("Module { dependencies: ['antono2.imgui@v0.3.1'] }")
        self.module = self.root / 'modules/antono2/imgui'
        self.module.mkdir(parents=True)
        (self.module / 'v.mod').write_text("Module { name: 'antono2.imgui' }")
        self.git('init', '-q')
        self.git('add', 'v.mod')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '-qm', 'fixture')
        self.git('tag', 'v0.3.1-standard')
        self.git('tag', 'v0.4.0-standard')

    def git(self, *args):
        subprocess.run(['git', '-C', str(self.module), *args], check=True,
                       capture_output=True, text=True)

    def check(self, *args):
        return subprocess.run([os.environ.get('V_BIN', 'v'), 'run',
                               str(self.root / 'scripts/check_installed_deps.vsh'), *args],
                              env=dict(os.environ, VMODULES=str(self.root / 'modules')),
                              capture_output=True, text=True)

    def test_independent_standard_version(self):
        result = self.check('--tag-override', 'antono2.imgui=v0.4.0-standard')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Verified antono2.imgui@v0.4.0-standard', result.stdout)

    def test_suffix_remains_supported(self):
        result = self.check('--tag-suffix', 'antono2.imgui=-standard')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_override_still_checks_actual_commit(self):
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '--allow-empty', '-qm', 'different head')
        result = self.check('--tag-override', 'antono2.imgui=v0.4.0-standard')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('does not match', result.stderr)

    def test_conflicting_selection_is_rejected(self):
        result = self.check('--tag-suffix', 'antono2.imgui=-standard',
                            '--tag-override', 'antono2.imgui=v0.4.0-standard')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('repeated tag selection', result.stderr)

    def test_unused_override_is_rejected(self):
        result = self.check('--tag-suffix', 'antono2.imgui=-standard',
                            '--tag-override', 'antono2.typo=v0.4.0-standard')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('did not match a dependency', result.stderr)


if __name__ == '__main__':
    unittest.main()
