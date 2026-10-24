"""Offline regressions for Picsee process enumeration before device actions."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import device as d


class ProcessQueryTests(unittest.TestCase):
    def query(self, status, output, error=''):
        result = subprocess.CompletedProcess(
            ['/usr/bin/pgrep', '-x', 'Picsee'], status, output, error)
        return patch.object(d, 'command', return_value=result)

    def test_success_returns_valid_pids(self):
        with self.query(0, '42\n9001\n'):
            self.assertEqual(d.running(), [42, 9001])

    def test_success_status_with_diagnostic_stderr_fails_closed(self):
        with self.query(0, '42\n', 'permission denied'):
            with self.assertRaisesRegex(RuntimeError, 'pgrep'):
                d.running()

    def test_exit_one_with_no_output_means_no_match(self):
        with self.query(1, ''):
            self.assertEqual(d.running(), [])

    def test_query_failures_are_explicit(self):
        for status in (2, 3, -9):
            with self.subTest(status=status), self.query(status, '', 'query unavailable'):
                with self.assertRaisesRegex(RuntimeError, 'pgrep'):
                    d.running()

    def test_malformed_or_contradictory_results_are_explicit(self):
        for status, output in ((0, ''), (1, '42\n'), (0, 'abc\n'),
                               (0, '42\nnot-a-pid\n'), (0, '0\n'),
                               (0, '1\n'), (0, '-42\n'),
                               (0, '42\n42\n'),
                               (0, '042\n42\n')):
            with self.subTest(status=status, output=output), self.query(status, output):
                with self.assertRaisesRegex(RuntimeError, 'pgrep'):
                    d.running()

    def test_no_match_with_stderr_or_unavailable_command_fails(self):
        with self.query(1, '', 'permission denied'):
            with self.assertRaisesRegex(RuntimeError, 'pgrep'):
                d.running()
        with patch.object(d, 'command', side_effect=OSError('pgrep unavailable')):
            with self.assertRaisesRegex(RuntimeError, 'pgrep'):
                d.running()
        with patch.object(d, 'command', side_effect=subprocess.TimeoutExpired('pgrep', 30)):
            with self.assertRaisesRegex(RuntimeError, 'pgrep'):
                d.running()

    def test_launch_stops_before_open_when_enumeration_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            (run / 'bundle.path').write_text(str(run / 'Picsee.app') + '\n')
            (run / 'build.json').write_text('{"sha":"abcdefg"}\n')
            with self.query(3, '', 'query unavailable'), \
                    patch.object(d, 'checked', side_effect=AssertionError('open must not run')) as checked:
                with self.assertRaisesRegex(RuntimeError, 'pgrep'):
                    d.launch(run)
                checked.assert_not_called()
            self.assertFalse((run / 'start.txt').exists())

    def test_doctor_fails_single_instance_on_query_error(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            app = run / 'Picsee.app'
            with self.query(3, '', 'query unavailable'), \
                    patch.object(d, 'identity', return_value=(42, app)), \
                    patch.object(d, 'windows', return_value=[]), \
                    patch.object(d, 'machine', return_value={}), \
                    patch.object(d, 'save'):
                data = d.collect(run, 'abc')
            self.assertFalse(data['alone'])
            self.assertIn('pgrep', data['errors']['single-instance'])
            lines, passed = d.verdicts(data)
            self.assertFalse(passed)
            self.assertTrue(any(line.startswith('FAIL single-instance — pgrep')
                                for line in lines), lines)


if __name__ == '__main__':
    unittest.main(verbosity=2)
