import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name('install-role.py')
spec = importlib.util.spec_from_file_location('install_role', SCRIPT)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallRoleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.rules = self.root / '.codex/rules'
        self.rules.mkdir(parents=True)
        (self.rules / 'picsee.rules').write_text('# common\n')
        self.overlay = self.rules / 'picsee-role.rules'

    def invoke(self, *args):
        with patch.object(sys, 'argv', ['install-role.py', '--worktree', str(self.root), *args]):
            installer.main()

    def test_omitted_role_is_restricted_implementor(self):
        self.invoke()
        self.assertTrue(self.overlay.read_text().startswith('# Local picsee role: implementor\n'))
        self.assertIn('pattern = ["git", "push"]', self.overlay.read_text())

    def test_symlink_target_is_rejected_without_touching_referent(self):
        referent = self.root / 'referent'
        referent.write_text('preserve')
        self.overlay.symlink_to(referent)
        with self.assertRaises(SystemExit):
            self.invoke('--role', 'delegator')
        self.assertEqual(referent.read_text(), 'preserve')

    def test_failed_replacement_preserves_existing_overlay_and_cleans_temp(self):
        self.overlay.write_text('preserve')
        with patch.object(installer.os, 'replace', side_effect=OSError('injected failure')):
            with self.assertRaises(OSError):
                self.invoke('--role', 'delegator')
        self.assertEqual(self.overlay.read_text(), 'preserve')
        self.assertEqual(list(self.rules.glob('.role-*')), [])


if __name__ == '__main__':
    unittest.main()
