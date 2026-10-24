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


if __name__ == "__main__":
    unittest.main()
