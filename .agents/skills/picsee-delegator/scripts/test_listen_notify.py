import importlib.util
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("listen-notify.py")
SPEC = importlib.util.spec_from_file_location("listen_notify", SCRIPT)
listen_notify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(listen_notify)
REPORT_SCRIPT = Path(__file__).with_name("poll-report.py")
REPORT_SPEC = importlib.util.spec_from_file_location("poll_report", REPORT_SCRIPT)
poll_report = importlib.util.module_from_spec(REPORT_SPEC)
REPORT_SPEC.loader.exec_module(poll_report)


class ListenerTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.handoff = self.root / "issue90-handoff.md"
        self.config = {
            "schema": 1,
            "event": "issue90-round-1-head-deadbee",
            "task": "issue90-round-1",
            "agent": "gpt-imple-3",
            "thread": "11111111-2222-4333-8444-555555555555",
            "handoff": str(self.handoff),
            "poll": ["/skill/scripts/poll-idle.sh", "gpt-imple-3", "120", "3000"],
            "created_at": 1_800_000_000.0,
            "max_delivery_attempts": 3,
            "initial_backoff_seconds": 1,
        }
        self.event_dir = self.root / "events" / self.config["event"]
        self.event_dir.mkdir(parents=True)
        (self.event_dir / "config.json").write_text(json.dumps(self.config))

    @staticmethod
    def completed(argv, returncode=0, stdout="", stderr=""):
        return subprocess.CompletedProcess(argv, returncode, stdout, stderr)

    def test_routes_to_exact_thread_and_successful_repeat_does_not_queue_again(self):
        self.handoff.write_text("DONE\n")
        os.utime(self.handoff, (1_800_000_001, 1_800_000_001))
        calls = []

        def run(argv, **kwargs):
            calls.append((argv, kwargs))
            if argv[0] == "/skill/scripts/poll-idle.sh":
                return self.completed(argv, stdout="gpt-imple-3 idle 12:00:00\n")
            return self.completed(argv, stdout='{"queued":true,"id":"q-1"}\n')

        self.assertEqual(listen_notify.run_event(self.event_dir, run=run), "delivered")
        self.assertEqual(listen_notify.run_event(self.event_dir, run=run), "already-delivered")

        queue_calls = [call for call in calls if call[0][0:2] == ["codex", "queue"]]
        self.assertEqual(len(queue_calls), 1)
        self.assertEqual(
            queue_calls[0][0][0:4],
            ["codex", "queue", "--thread", self.config["thread"]],
        )
        self.assertIn("--message", queue_calls[0][0])
        message = queue_calls[0][0][-1]
        self.assertIn(self.config["event"], message)
        self.assertIn(str(self.handoff), message)
        self.assertIn("poll completion is not audit acceptance", message.lower())
        receipt = json.loads((self.event_dir / "queue-receipt.json").read_text())
        self.assertEqual(receipt["event"], self.config["event"])
        self.assertEqual(receipt["queue_response"], '{"queued":true,"id":"q-1"}')

    def test_delivery_retries_with_bounded_backoff_and_marks_only_after_success(self):
        self.handoff.write_text("DONE\n")
        os.utime(self.handoff, (1_800_000_001, 1_800_000_001))
        queue_attempts = 0
        sleeps = []

        def run(argv, **kwargs):
            nonlocal queue_attempts
            if argv[0] != "codex":
                return self.completed(argv, stdout="gpt-imple-3 idle 12:00:00\n")
            queue_attempts += 1
            self.assertFalse((self.event_dir / "queue-receipt.json").exists())
            if queue_attempts < 3:
                return self.completed(argv, returncode=1, stderr="transport offline")
            return self.completed(argv, stdout="queued on third attempt")

        result = listen_notify.run_event(self.event_dir, run=run, sleep=sleeps.append)

        self.assertEqual(result, "delivered")
        self.assertEqual(queue_attempts, 3)
        self.assertEqual(sleeps, [1, 2])
        self.assertTrue((self.event_dir / "poll-result.json").exists())
        self.assertTrue((self.event_dir / "queue-receipt.json").exists())

    def test_exhausted_delivery_preserves_poll_evidence_for_later_retry(self):
        poll_calls = 0

        def fail(argv, **kwargs):
            nonlocal poll_calls
            if argv[0] != "codex":
                poll_calls += 1
                return self.completed(argv, stdout="gpt-imple-3 question 12:00:00\n")
            return self.completed(argv, returncode=1, stderr="transport offline")

        with self.assertRaises(listen_notify.DeliveryError):
            listen_notify.run_event(self.event_dir, run=fail, sleep=lambda _: None)

        self.assertEqual(poll_calls, 1)
        self.assertTrue((self.event_dir / "poll-result.json").exists())
        self.assertFalse((self.event_dir / "queue-receipt.json").exists())
        status = json.loads((self.event_dir / "status.json").read_text())
        self.assertEqual(status["state"], "delivery-failed")

        def recover(argv, **kwargs):
            if argv[0] != "codex":
                self.fail("a delivery retry must reuse retained poll evidence")
            return self.completed(argv, stdout="queued after recovery")

        self.assertEqual(listen_notify.run_event(self.event_dir, run=recover), "delivered")
        self.assertEqual(poll_calls, 1)

    def test_concurrent_delivery_for_same_event_queues_once(self):
        self.handoff.write_text("DONE\n")
        os.utime(self.handoff, (1_800_000_001, 1_800_000_001))
        (self.event_dir / "poll-result.json").write_text(
            json.dumps(
                {
                    "outcome": "idle",
                    "exit_code": 0,
                    "output": "gpt-imple-3 idle",
                    "handoff_evidence": "ready",
                }
            )
        )
        queue_calls = 0
        queue_started = threading.Event()
        allow_queue_to_finish = threading.Event()

        def run(argv, **kwargs):
            nonlocal queue_calls
            queue_calls += 1
            queue_started.set()
            allow_queue_to_finish.wait(timeout=2)
            return self.completed(argv, stdout="queued once")

        results = []
        threads = [
            threading.Thread(target=lambda: results.append(listen_notify.run_event(self.event_dir, run=run)))
            for _ in range(2)
        ]
        threads[0].start()
        self.assertTrue(queue_started.wait(timeout=2))
        threads[1].start()
        allow_queue_to_finish.set()
        for thread in threads:
            thread.join(timeout=2)

        self.assertEqual(queue_calls, 1)
        self.assertCountEqual(results, ["delivered", "already-delivered"])

    def test_reusing_event_with_different_identity_is_rejected(self):
        listen_notify.register_event(self.event_dir, self.config)
        changed = dict(self.config, thread="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")

        with self.assertRaisesRegex(listen_notify.EventIdentityError, "different identity"):
            listen_notify.register_event(self.event_dir, changed)

    def test_poll_failure_timeout_block_and_missing_or_stale_handoff_are_not_certified(self):
        cases = [
            (1, "poll crashed", "poll-error", "missing"),
            (0, "gpt-imple-3 timeout status=working", "timeout", "missing"),
            (0, "gpt-imple-3 blocked 12:00:00", "blocked", "missing"),
            (0, "gpt-imple-3 question 12:00:00", "question", "missing"),
            (0, "gpt-imple-3 idle 12:00:00", "idle", "missing"),
        ]
        for index, (returncode, output, outcome, evidence) in enumerate(cases):
            with self.subTest(outcome=outcome):
                event_dir = self.root / f"case-{index}"
                event_dir.mkdir()
                (event_dir / "config.json").write_text(json.dumps(self.config))
                messages = []

                def run(argv, **kwargs):
                    if argv[0] != "codex":
                        return self.completed(argv, returncode=returncode, stdout=output)
                    messages.append(argv[-1])
                    return self.completed(argv, stdout="queued")

                self.assertEqual(listen_notify.run_event(event_dir, run=run), "delivered")
                poll_result = json.loads((event_dir / "poll-result.json").read_text())
                self.assertEqual(poll_result["outcome"], outcome)
                self.assertEqual(poll_result["handoff_evidence"], evidence)
                self.assertIn("needs inspection", messages[0].lower())
                self.assertNotIn("accepted", messages[0].lower())

        self.handoff.write_text("old report")
        os.utime(self.handoff, (1_799_999_999, 1_799_999_999))
        stale_dir = self.root / "stale"
        stale_dir.mkdir()
        (stale_dir / "config.json").write_text(json.dumps(self.config))

        def stale_run(argv, **kwargs):
            if argv[0] != "codex":
                return self.completed(argv, stdout="gpt-imple-3 idle 12:00:00")
            return self.completed(argv, stdout="queued")

        listen_notify.run_event(stale_dir, run=stale_run)
        result = json.loads((stale_dir / "poll-result.json").read_text())
        self.assertEqual(result["handoff_evidence"], "stale")

    def test_report_mode_requires_round_marker_and_binds_it_to_event_identity(self):
        parser = listen_notify._build_parser()
        args = parser.parse_args([
            "start", "--event", "new-round", "--task", "issue90-confirm3",
            "--thread", self.config["thread"], "--agent", "gpt-auditor",
            "--handoff", str(self.handoff), "--poll", "report",
            "--handoff-marker", "issue90-confirm3", "--interval", "2",
            "--max-minutes", "10",
        ])
        config = listen_notify._config_from_args(args)
        self.assertEqual(Path(config["poll"][0]).name, "poll-report.py")
        self.assertIn("issue90-confirm3", config["poll"])
        self.assertEqual(config["handoff_marker"], "issue90-confirm3")
        report_event_dir = self.root / "report-repeat"
        listen_notify.register_event(report_event_dir, config)
        self.assertEqual(
            listen_notify.register_event(report_event_dir, listen_notify._config_from_args(args)),
            "already-registered",
        )
        with self.assertRaisesRegex(ValueError, "handoff_marker"):
            listen_notify._validate_config(dict(config, handoff_marker=None))
        with self.assertRaisesRegex(ValueError, "handoff_marker"):
            listen_notify._validate_config(dict(config, handoff_marker="DONE"))

    def test_report_mode_rejects_blank_identity_at_cli_and_persisted_boundaries(self):
        parser = listen_notify._build_parser()
        for task, marker in (("", ""), ("   ", "   "), ("issue90-r1", "  ")):
            with self.subTest(task=task, marker=marker):
                args = parser.parse_args([
                    "start", "--event", "blank-round", "--task", task,
                    "--thread", self.config["thread"], "--agent", "gpt-auditor",
                    "--handoff", str(self.handoff), "--poll", "report",
                    "--handoff-marker", marker,
                ])
                with self.assertRaisesRegex(ValueError, "non-empty"):
                    listen_notify._config_from_args(args)
                persisted = dict(self.config, task=task, handoff_marker=marker,
                                 poll=[str(REPORT_SCRIPT), "gpt-auditor", str(self.handoff)])
                (self.event_dir / "config.json").write_text(json.dumps(persisted))
                with self.assertRaisesRegex(ValueError, "non-empty"):
                    listen_notify.run_event(self.event_dir, run=lambda *_args, **_kwargs: self.fail("must not poll"))

    def test_idle_with_old_matching_report_waits_for_fresh_report(self):
        self.handoff.write_text("Report-Task: issue90-r1\n")
        os.utime(self.handoff, (1_799_999_999, 1_799_999_999))
        observations = []

        def status(_agent):
            observations.append("idle")
            return "idle"

        def advance(_seconds):
            if len(observations) == 2:
                os.utime(self.handoff, (1_800_000_001, 1_800_000_001))

        result = poll_report.watch(
            "gpt-auditor", self.handoff, 1_800_000_000, "issue90-r1",
            interval=1, max_minutes=1, idle_grace_seconds=5,
            get_status=status, sleep=advance,
            monotonic=iter([0, 0, 1, 2]).__next__,
        )
        self.assertEqual(result, "done")
        self.assertEqual(len(observations), 3, "old report must not stop polling")

    def test_done_with_fresh_wrong_identity_waits_for_correct_report(self):
        self.handoff.write_text("Report-Task: issue90-r10\n")
        os.utime(self.handoff, (1_800_000_001, 1_800_000_001))
        observations = []

        def status(_agent):
            observations.append("done")
            return "done"

        def advance(_seconds):
            if len(observations) == 2:
                self.handoff.write_text("Report-Task: issue90-r1\n")
                os.utime(self.handoff, (1_800_000_002, 1_800_000_002))

        result = poll_report.watch(
            "gpt-auditor", self.handoff, 1_800_000_000, "issue90-r1",
            interval=1, max_minutes=1, idle_grace_seconds=5,
            get_status=status, sleep=advance,
            monotonic=iter([0, 0, 1, 2]).__next__,
        )
        self.assertEqual(result, "done")
        self.assertEqual(len(observations), 3, "wrong task must not stop polling")

    def test_report_identity_field_must_be_unique_and_poll_path_must_match_config(self):
        self.handoff.write_text("Report-Task: issue90-r1\nReport-Task: issue90-r1\n")
        os.utime(self.handoff, (1_800_000_001, 1_800_000_001))
        self.assertFalse(poll_report._fresh_report(self.handoff, 1_800_000_000, "issue90-r1"))
        config = dict(self.config, task="issue90-r1", handoff_marker="issue90-r1",
                      poll=[str(REPORT_SCRIPT), "gpt-auditor", str(self.root / "other.md"),
                            str(self.event_dir / "config.json"), "issue90-r1", "1", "1", "1"])
        with self.assertRaisesRegex(ValueError, "report path"):
            listen_notify._validate_config(config)

    def test_report_poll_finds_fresh_report_at_idle_despite_scrolled_viewport(self):
        self.handoff.write_text("Report-Task: issue90-confirm3\nDONE\n")
        os.utime(self.handoff, (1_800_000_001, 1_800_000_001))
        statuses = iter(["working", "idle"])
        screens = ["Back to bottom; older activity", "Back to bottom; older activity"]
        result = poll_report.watch(
            "gpt-auditor", self.handoff, 1_800_000_000, "issue90-confirm3",
            interval=2, max_minutes=10, idle_grace_seconds=4,
            get_status=lambda _: next(statuses), sleep=lambda _: screens.pop(),
            monotonic=iter([0, 0, 2]).__next__,
        )
        self.assertEqual(result, "done")

    def test_old_report_does_not_complete_new_working_task(self):
        self.handoff.write_text("# issue90-old-round\nDONE\n")
        os.utime(self.handoff, (1_799_999_999, 1_799_999_999))
        times = iter([0, 0, 2, 4, 6])
        result = poll_report.watch(
            "gpt-auditor", self.handoff, 1_800_000_000, "issue90-new-round",
            interval=2, max_minutes=0.1, idle_grace_seconds=4,
            get_status=lambda _: "working", sleep=lambda _: None,
            monotonic=times.__next__,
        )
        self.assertEqual(result, "timeout")

    def test_idle_without_report_surfaces_missing_handoff_after_grace(self):
        times = iter([0, 0, 2, 4])
        result = poll_report.watch(
            "gpt-auditor", self.handoff, 1_800_000_000, "issue90-new-round",
            interval=2, max_minutes=10, idle_grace_seconds=4,
            get_status=lambda _: "idle", sleep=lambda _: None,
            monotonic=times.__next__,
        )
        self.assertEqual(result, "missing-handoff")
        self.assertEqual(listen_notify._classify_poll(0, "gpt-auditor missing-handoff"), "missing-handoff")

    def test_blocked_without_report_surfaces_immediately(self):
        result = poll_report.watch(
            "gpt-auditor", self.handoff, 1_800_000_000, "issue90-new-round",
            interval=2, max_minutes=10, idle_grace_seconds=4,
            get_status=lambda _: "blocked", sleep=lambda _: self.fail("blocked must not sleep"),
            monotonic=iter([0, 0]).__next__,
        )
        self.assertEqual(result, "blocked")

    def test_report_mode_worker_uses_fake_herdr_and_queue_without_viewport(self):
        fake_bin = self.root / "fake-report-bin"
        fake_bin.mkdir()
        captured = self.root / "report-message.txt"
        herdr = fake_bin / "herdr"
        herdr.write_text("#!/bin/sh\nprintf '%s\\n' '{\"agent_status\":\"idle\"}'\n")
        herdr.chmod(0o755)
        codex = fake_bin / "codex"
        codex.write_text(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            "open(os.environ['CAPTURED_MESSAGE'], 'w').write(sys.argv[-1])\n"
            "print('scratch queued')\n"
        )
        codex.chmod(0o755)
        args = listen_notify._build_parser().parse_args([
            "start", "--event", self.event_dir.name, "--task", "issue90-report-test",
            "--thread", self.config["thread"], "--agent", "gpt-auditor",
            "--handoff", str(self.handoff), "--handoff-marker", "issue90-report-test",
            "--poll", "report", "--interval", "1", "--max-minutes", "1",
            "--state-root", str(self.event_dir.parent),
        ])
        config = listen_notify._config_from_args(args)
        self.handoff.write_text("Report-Task: issue90-report-test\nCompleted\n")
        (self.event_dir / "config.json").write_text(json.dumps(config))
        environment = dict(os.environ, CAPTURED_MESSAGE=str(captured))
        environment["PATH"] = str(fake_bin) + os.pathsep + environment["PATH"]
        completed = subprocess.run(
            [sys.executable, str(SCRIPT), "run", "--event-dir", str(self.event_dir)],
            capture_output=True, text=True, env=environment, timeout=5,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads((self.event_dir / "poll-result.json").read_text())
        self.assertEqual(result["outcome"], "done")
        self.assertEqual(result["handoff_evidence"], "ready")
        self.assertIn("issue90-report-test", captured.read_text())

    def test_real_report_worker_rejects_prefix_collision_and_blank_config(self):
        fake_bin = self.root / "fake-identity-bin"
        fake_bin.mkdir()
        herdr = fake_bin / "herdr"
        herdr.write_text("#!/bin/sh\nprintf '%s\\n' '{\"agent_status\":\"idle\"}'\n")
        herdr.chmod(0o755)
        codex = fake_bin / "codex"
        codex.write_text("#!/bin/sh\nprintf 'scratch queued\\n'\n")
        codex.chmod(0o755)
        environment = dict(os.environ)
        environment["PATH"] = str(fake_bin) + os.pathsep + environment["PATH"]
        args = listen_notify._build_parser().parse_args([
            "start", "--event", self.event_dir.name, "--task", "issue90-r1",
            "--thread", self.config["thread"], "--agent", "gpt-auditor",
            "--handoff", str(self.handoff), "--handoff-marker", "issue90-r1",
            "--poll", "report", "--interval", "1", "--max-minutes", "1",
            "--idle-grace-seconds", "1", "--state-root", str(self.event_dir.parent),
        ])
        config = listen_notify._config_from_args(args)
        self.handoff.write_text("Report-Task: issue90-r10\n")
        os.utime(self.handoff, (config["created_at"] + 1, config["created_at"] + 1))
        (self.event_dir / "config.json").write_text(json.dumps(config))
        completed = subprocess.run(
            [sys.executable, str(SCRIPT), "run", "--event-dir", str(self.event_dir)],
            capture_output=True, text=True, env=environment, timeout=5,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads((self.event_dir / "poll-result.json").read_text())
        self.assertEqual(result["outcome"], "missing-handoff")
        self.assertEqual(result["handoff_evidence"], "stale")
        self.assertTrue((self.event_dir / "queue-receipt.json").exists())

        blank_dir = self.root / "blank-worker"
        blank_dir.mkdir()
        (blank_dir / "config.json").write_text(json.dumps(dict(config, task="", handoff_marker="")))
        blank = subprocess.run(
            [sys.executable, str(SCRIPT), "run", "--event-dir", str(blank_dir)],
            capture_output=True, text=True, env=environment, timeout=5,
        )
        self.assertNotEqual(blank.returncode, 0)
        self.assertIn("non-empty", blank.stderr)
        self.assertFalse((blank_dir / "queue-receipt.json").exists())

    def test_detached_start_uses_argv_writes_pid_and_does_not_shell_interpolate(self):
        launches = []

        class Process:
            pid = 4242

        def launch(argv, **kwargs):
            launches.append((argv, kwargs))
            return Process()

        result = listen_notify.start_listener(self.event_dir, self.config, launch=launch)

        self.assertEqual(result, "started")
        self.assertEqual((self.event_dir / "pid").read_text(), "4242\n")
        argv, kwargs = launches[0]
        self.assertIsInstance(argv, list)
        self.assertEqual(argv[-2:], ["--event-dir", str(self.event_dir)])
        self.assertTrue(kwargs["start_new_session"])
        self.assertIs(kwargs["stdin"], subprocess.DEVNULL)
        self.assertNotIn("shell", kwargs)

    def test_cli_run_uses_a_scratch_transport_and_never_queues_a_real_thread(self):
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        captured = self.root / "captured-argv.json"
        fake_codex = fake_bin / "codex"
        fake_codex.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "open(os.environ['CAPTURED_ARGV'], 'w').write(json.dumps(sys.argv[1:]))\n"
            "print('scratch queue receipt')\n"
        )
        fake_codex.chmod(0o755)
        self.handoff.write_text("DONE\n")
        os.utime(self.handoff, (1_800_000_001, 1_800_000_001))
        self.config["poll"] = [
            sys.executable,
            "-c",
            "print('gpt-imple-3 idle 12:00:00')",
        ]
        (self.event_dir / "config.json").write_text(json.dumps(self.config))
        environment = dict(os.environ)
        environment["PATH"] = str(fake_bin) + os.pathsep + environment["PATH"]
        environment["CAPTURED_ARGV"] = str(captured)

        completed = subprocess.run(
            [sys.executable, str(SCRIPT), "run", "--event-dir", str(self.event_dir)],
            capture_output=True,
            text=True,
            env=environment,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stdout.strip(), "delivered")
        argv = json.loads(captured.read_text())
        self.assertEqual(argv[0:3], ["queue", "--thread", self.config["thread"]])
        self.assertEqual(argv[3], "--message")
        self.assertTrue((self.event_dir / "queue-receipt.json").exists())

    def test_real_hung_poller_and_resistant_child_time_out_notify_and_exit(self):
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        captured = self.root / "captured-argv.json"
        codex = fake_bin / "codex"
        codex.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "open(os.environ['CAPTURED_ARGV'], 'w').write(json.dumps(sys.argv[1:]))\n"
            "print('scratch queue receipt')\n"
        )
        codex.chmod(0o755)
        child_pid_path = self.root / "child.pid"
        hung_poll = self.root / "hung-poll.py"
        hung_poll.write_text(
            "import os, signal, subprocess, sys, time\n"
            "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
            "child = subprocess.Popen([sys.executable, '-c', "
            "'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'])\n"
            "open(sys.argv[1], 'w').write(str(child.pid))\n"
            "time.sleep(60)\n"
        )
        self.config["poll"] = [sys.executable, str(hung_poll), str(child_pid_path)]
        self.config["poll_deadline_seconds"] = 0.25
        self.handoff.write_text("DONE\n")
        os.utime(self.handoff, (1_800_000_001, 1_800_000_001))
        (self.event_dir / "config.json").write_text(json.dumps(self.config))
        environment = dict(os.environ)
        environment["PATH"] = str(fake_bin) + os.pathsep + environment["PATH"]
        environment["CAPTURED_ARGV"] = str(captured)
        worker = subprocess.Popen(
            [sys.executable, str(SCRIPT), "run", "--event-dir", str(self.event_dir)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
            start_new_session=True,
        )
        bystander = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(5)"], start_new_session=True
        )
        try:
            try:
                stdout, stderr = worker.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                self.fail("listener exceeded its short poll deadline")
            self.assertEqual(worker.returncode, 0, stderr)
            self.assertEqual(stdout.strip(), "delivered")
            result = json.loads((self.event_dir / "poll-result.json").read_text())
            self.assertEqual(result["outcome"], "timeout")
            self.assertEqual(result["exit_code"], None)
            self.assertEqual(result["handoff_evidence"], "ready")
            argv = json.loads(captured.read_text())
            self.assertIn("needs inspection", argv[-1].lower())
            self.assertIn("timeout", argv[-1].lower())
            self.assertIsNone(bystander.poll(), "cleanup signalled an unrelated process group")
            child_pid = int(child_pid_path.read_text())
            for _ in range(20):
                try:
                    os.kill(child_pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.05)
            else:
                self.fail("hung poller child survived cleanup")
        finally:
            if worker.poll() is None:
                os.killpg(worker.pid, signal.SIGKILL)
                worker.communicate(timeout=2)
            if bystander.poll() is None:
                bystander.kill()
            bystander.wait(timeout=2)

    def test_exited_poller_reaps_inherited_output_child_before_delivery(self):
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        captured = self.root / "captured-argv.json"
        codex = fake_bin / "codex"
        codex.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "open(os.environ['CAPTURED_ARGV'], 'w').write(json.dumps(sys.argv[1:]))\n"
            "print('scratch queue receipt')\n"
        )
        codex.chmod(0o755)
        child_pid_path = self.root / "child.pid"
        poller = self.root / "exiting-poll.py"
        poller.write_text(
            "import subprocess, sys\n"
            "child = subprocess.Popen([sys.executable, '-c', "
            "'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'])\n"
            "open(sys.argv[1], 'w').write(str(child.pid))\n"
            "print('gpt-imple-3 idle 12:00:00', flush=True)\n"
        )
        self.config["poll"] = [sys.executable, str(poller), str(child_pid_path)]
        self.config["poll_deadline_seconds"] = 0.5
        self.handoff.write_text("DONE\n")
        os.utime(self.handoff, (1_800_000_001, 1_800_000_001))
        (self.event_dir / "config.json").write_text(json.dumps(self.config))
        environment = dict(os.environ)
        environment["PATH"] = str(fake_bin) + os.pathsep + environment["PATH"]
        environment["CAPTURED_ARGV"] = str(captured)
        worker = subprocess.Popen(
            [sys.executable, str(SCRIPT), "run", "--event-dir", str(self.event_dir)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=environment,
            start_new_session=True,
        )
        bystander = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(5)"], start_new_session=True
        )
        try:
            stdout, stderr = worker.communicate(timeout=3)
            self.assertEqual(worker.returncode, 0, stderr)
            self.assertEqual(stdout.strip(), "delivered")
            result = json.loads((self.event_dir / "poll-result.json").read_text())
            self.assertEqual(result["outcome"], "idle")
            self.assertEqual(result["handoff_evidence"], "ready")
            self.assertIsNone(bystander.poll())
            argv = json.loads(captured.read_text())
            self.assertIn("idle", argv[-1].lower())
            child_pid = int(child_pid_path.read_text())
            for _ in range(20):
                try:
                    os.kill(child_pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.05)
            else:
                self.fail("exited poller left its inherited-output child alive")
        finally:
            if child_pid_path.exists():
                try:
                    os.kill(int(child_pid_path.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if worker.poll() is None:
                os.killpg(worker.pid, signal.SIGKILL)
                worker.communicate(timeout=2)
            if bystander.poll() is None:
                bystander.kill()
            bystander.wait(timeout=2)


if __name__ == "__main__":
    unittest.main()
