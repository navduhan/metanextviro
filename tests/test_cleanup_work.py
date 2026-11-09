"""Check cleanup guards without deleting real task data."""
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('cleanup_work', ROOT / 'scripts/cleanup_work.py')
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)
HISTORY = ('TIMESTAMP\tDURATION\tRUN NAME    \tSTATUS\tREVISION ID\tSESSION ID\tCOMMAND\n'
           '2026-11-03 01:00\t1s\tsuccess_run \tOK    \taaaa\tgood-session\tnextflow run main.nf\n'
           '2026-11-03 01:01\t1s\tfailed_run  \tERR   \taaaa\tbad-session\tnextflow run main.nf\n')


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.results = self.root / 'results'
        self.results.mkdir()
        (self.results / 'report.tsv').write_text('retained results\n')

    def test_history_padding_and_explicit_session_lookup(self):
        self.assertEqual(cleanup.successful_run(HISTORY, 'success_run'), 'success_run')
        self.assertEqual(cleanup.successful_run(HISTORY, 'good-session'), 'success_run')

    def test_failed_missing_and_unreadable_runs_are_rejected(self):
        for history, name in [(HISTORY, 'failed_run'), (HISTORY, 'missing'), ('invalid output', 'success_run')]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                cleanup.successful_run(history, name)

    def test_latest_attempt_status_is_required(self):
        history = HISTORY + '2026-11-03 01:02\t1s\tsuccess_run\tERR\taaaa\tgood-session\tresume\n'
        with self.assertRaisesRegex(ValueError, 'did not finish successfully'):
            cleanup.successful_run(history, 'good-session')

    def test_older_success_cannot_clean_a_later_unfinished_resume(self):
        history = HISTORY + '2026-11-03 01:02\t-\tresuming_run\t-\taaaa\tgood-session\tresume\n'
        with self.assertRaisesRegex(ValueError, 'later attempt'):
            cleanup.successful_run(history, 'success_run')

    def test_symbolic_link_results_are_rejected(self):
        (self.results / 'external.tsv').symlink_to(self.root / 'missing_work_output.tsv')
        with self.assertRaisesRegex(ValueError, 'symbolic link'):
            cleanup.validate_results(self.results, [])

    def test_empty_and_overlapping_result_trees_are_rejected(self):
        empty = self.root / 'empty'
        empty.mkdir()
        with self.assertRaisesRegex(ValueError, 'no files'):
            cleanup.validate_results(empty, [])
        for work in [self.results, self.root, self.results / 'task']:
            with self.subTest(work=work), self.assertRaisesRegex(ValueError, 'overlap'):
                cleanup.validate_results(self.results, [work])

    def test_default_is_named_log_preserving_dry_run(self):
        with patch.object(cleanup, 'nextflow_output', side_effect=[HISTORY, str(self.root / 'work/task') + '\n']), \
             patch.object(cleanup.subprocess, 'run') as execute:
            cleanup.main(['--run', 'success_run', '--results', 'results', '--launch-dir', str(self.root)])
        execute.assert_called_once_with(['nextflow', 'clean', 'success_run', '-keep-logs', '-dry-run'],
                                        cwd=self.root.resolve(), check=True)

    def test_apply_is_explicit_and_preserves_logs(self):
        with patch.object(cleanup, 'nextflow_output', side_effect=[HISTORY, str(self.root / 'work/task') + '\n']), \
             patch.object(cleanup.subprocess, 'run') as execute:
            cleanup.main(['--run', 'good-session', '--results', 'results', '--launch-dir', str(self.root), '--apply'])
        execute.assert_called_once_with(['nextflow', 'clean', 'success_run', '-keep-logs', '-force'],
                                        cwd=self.root.resolve(), check=True)


if __name__ == '__main__':
    unittest.main()
