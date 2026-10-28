import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("rebase-ledger.sh")
# A stand-in for scripts/ledger/build.mjs: regenerates the HTML from the Markdown and supports --check.
STUB_BUILD = """import fs from 'node:fs';
const html = '<p>' + fs.readFileSync('docs/feature-ledger.md', 'utf8').trim() + '</p>\\n';
if (process.argv.includes('--check')) process.exit(fs.readFileSync('docs/feature-ledger.html', 'utf8') === html ? 0 : 1);
fs.writeFileSync('docs/feature-ledger.html', html);
"""


def git(cwd, *args, env=None):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True, env=env).stdout


class RebaseLedgerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.origin, self.work = root / "origin", root / "work"
        self.env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
                    "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid"}
        self.origin.mkdir()
        git(self.origin, "init", "-q", "-b", "main", env=self.env)
        (self.origin / "scripts/ledger").mkdir(parents=True)
        (self.origin / "scripts/ledger/build.mjs").write_text(STUB_BUILD)
        (self.origin / "docs").mkdir()
        self.write(self.origin, "docs/feature-ledger.md", "base\n")
        self.write(self.origin, "docs/feature-ledger.html", "<p>base</p>\n")
        self.write(self.origin, "code.txt", "base\n")
        git(self.origin, "add", ".", env=self.env)
        git(self.origin, "commit", "-qm", "init", env=self.env)
        git(root, "clone", "-q", str(self.origin), str(self.work), env=self.env)
        git(self.work, "switch", "-qc", "topic", env=self.env)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, repo, path, text):
        (repo / path).write_text(text)

    def commit(self, repo, message, **files):
        for path, text in files.items():
            self.write(repo, path, text)
        git(repo, "add", *files, env=self.env)
        git(repo, "commit", "-qm", message, env=self.env)

    def run_script(self):
        return subprocess.run(["zsh", str(SCRIPT), "origin/main"], cwd=self.work, capture_output=True, text=True,
                              env=self.env)

    def test_resolved_html_conflict_keeps_body_lines_starting_with_hash(self):
        self.commit(self.origin, "docs: main side", **{"docs/feature-ledger.html": "<p>main</p>\n"})
        message = "feat(grid): topic\n\n#123 P2-05 FOLDER-06\nsecond line\n\nImplemented-by: t"
        self.commit(self.work, message, **{"docs/feature-ledger.html": "<p>topic</p>\n", "code.txt": "topic\n"})

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("DONE resolved", result.stdout)
        self.assertEqual(git(self.work, "log", "-1", "--format=%B").strip(), message)

    def test_conflict_outside_the_ledger_stops_with_the_rebase_in_progress(self):
        self.commit(self.origin, "fix: main side", **{"code.txt": "main\n"})
        self.commit(self.work, "fix: topic side", **{"code.txt": "topic\n"})

        result = self.run_script()

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("STOP other conflict: code.txt", result.stdout)
        self.assertTrue((self.work / ".git/rebase-merge").is_dir())


class RebaseVerifyTests(unittest.TestCase):
    """rebase-verify.sh compares an audited range with its rebased range."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        self.env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
                    "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid"}
        git(self.repo, "init", "-q", "-b", "main", env=self.env)
        (self.repo / "App").mkdir()
        self.commit("init", **{"App/a.swift": "a\n", "App/b.swift": "b\n", "notes.md": "n\n"})
        self.old_base = self.head()
        self.commit("feat: topic\n\n#7 P1-01 VIEW-01", **{"App/a.swift": "a2\n"})
        self.old_head = self.head()
        git(self.repo, "switch", "-qc", "rebased", self.old_base, env=self.env)
        self.commit("docs: main moved", **{"notes.md": "n2\n", "App/b.swift": "b2\n"})
        self.new_base = self.head()

    def tearDown(self):
        self.tmp.cleanup()

    def head(self):
        return git(self.repo, "rev-parse", "HEAD").strip()

    def commit(self, message, **files):
        for path, text in files.items():
            (self.repo / path).write_text(text)
        git(self.repo, "add", *files, env=self.env)
        git(self.repo, "commit", "-qm", message, env=self.env)

    def verify(self):
        return subprocess.run(["zsh", str(Path(__file__).with_name("rebase-verify.sh")), self.old_base, self.old_head,
                               self.new_base, self.head()], cwd=self.repo, capture_output=True, text=True)

    def test_same_patch_on_a_moved_base_passes(self):
        self.commit("feat: topic\n\n#7 P1-01 VIEW-01", **{"App/a.swift": "a2\n"})

        result = self.verify()

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("MESSAGES same", result.stdout)
        self.assertIn("CODE same", result.stdout)

    def test_conflict_resolution_that_changes_code_exits_1(self):
        self.commit("feat: topic\n\n#7 P1-01 VIEW-01", **{"App/a.swift": "a3\n"})

        result = self.verify()

        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("CODE differ", result.stdout)

    def test_dropped_hash_line_exits_2(self):
        self.commit("feat: topic", **{"App/a.swift": "a2\n"})

        result = self.verify()

        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("MESSAGES differ", result.stdout)

    def test_unknown_commit_exits_3(self):
        result = subprocess.run(["zsh", str(Path(__file__).with_name("rebase-verify.sh")), "nope", "HEAD", "HEAD",
                                 "HEAD"], cwd=self.repo, capture_output=True, text=True)

        self.assertEqual(result.returncode, 3, result.stdout)


class OwnerGatesRefusalTests(unittest.TestCase):
    """owner-gates.sh must refuse rather than gate the wrong code; a full run is exercised on real heads."""

    def run_gates(self, worktree, sha):
        with tempfile.TemporaryDirectory() as out:
            result = subprocess.run(["zsh", str(Path(__file__).with_name("owner-gates.sh")), worktree, sha, "t"],
                                    capture_output=True, text=True, env={**os.environ, "PICSEE_GATES_OUT": out})
            return result.returncode, (Path(out) / "t-summary.txt").read_text()

    def test_head_mismatch_writes_no_gate_results(self):
        rc, summary = self.run_gates(str(Path(__file__).resolve().parent), "0" * 40)

        self.assertEqual(rc, 2)
        self.assertEqual(summary.strip(), "head mismatch")

    def test_missing_worktree_is_refused(self):
        rc, summary = self.run_gates("/nonexistent-picsee-worktree", "HEAD")

        self.assertEqual(rc, 2)
        self.assertIn("no worktree", summary)


if __name__ == "__main__":
    unittest.main()


class ResolvePart3Tests(unittest.TestCase):
    """Part 3 conflicts merge both sides; main's notes and dates are never dropped (2026-10-28 #243 near-miss)."""

    def run_resolve(self, text):
        import importlib.util
        spec = importlib.util.spec_from_file_location('resolve_part3', Path(__file__).with_name('resolve_part3.py'))
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        return mod.resolve(text)

    def test_keeps_main_note_and_date_and_appends_branch_sentence(self):
        text = ('| 区域 | 最近审查 | 审查人 | 备注 |\n'
                '<<<<<<< HEAD\n'
                '| 网格 | 2026-10-28 | doc-gardener | 主线注一。主线注二。 |\n'
                '=======\n'
                '| 网格 | 2026-10-27 | doc-gardener | 主线注一。分支注。 |\n'
                '>>>>>>> abc (garden)\n')
        out, ok = self.run_resolve(text)
        self.assertTrue(ok)
        self.assertIn('| 网格 | 2026-10-28 | doc-gardener | 主线注一。主线注二。分支注。 |', out)
        self.assertNotIn('2026-10-27', out)
        self.assertNotIn('<<<<<<<', out)

    def test_branch_only_row_is_kept(self):
        text = ('<<<<<<< HEAD\n| 甲 | 2026-10-28 | g | 甲注。 |\n=======\n'
                '| 甲 | 2026-10-28 | g | 甲注。 |\n| 乙 | 2026-10-28 | g | 乙注。 |\n>>>>>>> x\n')
        out, ok = self.run_resolve(text)
        self.assertTrue(ok)
        self.assertIn('| 乙 | 2026-10-28 | g | 乙注。 |', out)

    def test_non_row_conflict_is_left_unresolved(self):
        text = '<<<<<<< HEAD\nprose A\n=======\nprose B\n>>>>>>> x\n'
        out, ok = self.run_resolve(text)
        self.assertFalse(ok)
        self.assertIn('<<<<<<<', out)
