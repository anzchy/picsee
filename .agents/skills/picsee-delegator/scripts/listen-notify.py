#!/usr/bin/env python3
"""Run a shipped roster poller, then notify one explicitly named Codex thread."""

import argparse
import fcntl
import json
import math
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path


class DeliveryError(RuntimeError):
    """The queue transport failed after all configured attempts."""


class EventIdentityError(RuntimeError):
    """An event ID was reused for a different task or destination."""


IDENTITY_FIELDS = ("event", "task", "agent", "thread", "handoff", "handoff_marker", "poll")
REQUIRED_FIELDS = ("schema", "event", "task", "agent", "thread", "handoff", "poll", "created_at")
EVENT_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_THREAD_LOCKS = {}
_THREAD_LOCKS_GUARD = threading.Lock()


def _atomic_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + ".tmp-" + str(os.getpid()))
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    os.replace(str(temporary), str(path))


def _read_json(path):
    return json.loads(Path(path).read_text())


def _identity(config):
    return {field: config.get(field) for field in IDENTITY_FIELDS}


def _validate_config(config):
    missing = [field for field in REQUIRED_FIELDS if field not in config]
    if missing:
        raise ValueError("missing config fields: " + ", ".join(missing))
    if config["schema"] != 1:
        raise ValueError("unsupported config schema")
    if not EVENT_PATTERN.fullmatch(config["event"]):
        raise ValueError("event must use only letters, numbers, dot, underscore, or hyphen")
    try:
        uuid.UUID(config["thread"])
    except (AttributeError, TypeError, ValueError) as error:
        raise ValueError("thread must be an explicit UUID") from error
    handoff = Path(config["handoff"])
    if not handoff.is_absolute():
        raise ValueError("handoff must be an absolute path")
    poll = config["poll"]
    if not isinstance(poll, list) or not poll or not all(isinstance(item, str) for item in poll):
        raise ValueError("poll must be a non-empty argv list")
    if Path(poll[0]).name == "poll-report.py" and config.get("handoff_marker") != config["task"]:
        raise ValueError("report polling requires handoff_marker equal to task identity")
    attempts = config.get("max_delivery_attempts", 5)
    backoff = config.get("initial_backoff_seconds", 5)
    if not isinstance(attempts, int) or attempts < 1 or attempts > 10:
        raise ValueError("max_delivery_attempts must be between 1 and 10")
    if not isinstance(backoff, (int, float)) or backoff < 0 or backoff > 300:
        raise ValueError("initial_backoff_seconds must be between 0 and 300")
    deadline = config.get("poll_deadline_seconds")
    if deadline is not None and (
        not isinstance(deadline, (int, float)) or not math.isfinite(deadline) or deadline <= 0
    ):
        raise ValueError("poll_deadline_seconds must be finite and positive")


def _thread_lock(path):
    key = str(Path(path).resolve())
    with _THREAD_LOCKS_GUARD:
        return _THREAD_LOCKS.setdefault(key, threading.Lock())


@contextmanager
def _locked(path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with _thread_lock(path):
        with Path(path).open("a") as lock_file:
            fcntl.flock(lock_file, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock_file, fcntl.LOCK_UN)


def register_event(event_dir, config):
    """Persist an immutable event identity under a short registration lock."""
    _validate_config(config)
    event_dir = Path(event_dir)
    event_dir.mkdir(parents=True, exist_ok=True)
    config_path = event_dir / "config.json"
    with _locked(event_dir / "register.lock"):
        if config_path.exists():
            existing = _read_json(config_path)
            if _identity(existing) != _identity(config):
                raise EventIdentityError(
                    "event ID already exists with a different identity: " + config["event"]
                )
            return "already-registered"
        _atomic_json(config_path, config)
        return "registered"


def _handoff_evidence(config):
    handoff = Path(config["handoff"])
    if not handoff.exists():
        return "missing"
    marker = config.get("handoff_marker")
    if marker and marker not in handoff.read_text(errors="replace"):
        return "stale"
    if handoff.stat().st_mtime < config["created_at"]:
        return "stale"
    return "ready"


def _classify_poll(returncode, output):
    lowered = output.lower()
    if returncode != 0:
        return "timeout" if re.search(r"\btimeout\b", lowered) else "poll-error"
    for outcome in ("missing-handoff", "question", "blocked", "timeout", "idle", "done"):
        if re.search(r"\b" + outcome + r"\b", lowered):
            return outcome
    return "poll-error"


def _poll_deadline_seconds(config):
    if "poll_deadline_seconds" in config:
        return config["poll_deadline_seconds"]
    # Existing registered events predate the stored deadline. Recover the shipped
    # poller's configured maximum rather than silently giving them an infinite wait.
    poll = config["poll"]
    name = Path(poll[0]).name
    if name in ("poll-idle.sh", "poll-handoff.sh") and len(poll) >= 4:
        try:
            minutes = int(poll[3])
            interval = int(poll[2]) if name == "poll-idle.sh" else 60
            if minutes > 0 and interval > 0:
                return minutes * 60 + interval + 10
        except ValueError:
            pass
    if name == "poll-report.py" and len(poll) >= 7:
        try:
            return float(poll[6]) * 60 + float(poll[5]) + 10
        except (IndexError, ValueError):
            pass
    return 600 * 60 + 70


def _run_poll_process(argv, deadline):
    # A file avoids waiting forever on a pipe still held open by a hung descendant.
    with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryFile(mode="w+t") as output:
        status = Path(temporary) / "poll-exit-code"
        # Keep the private group leader alive after the poller exits. Its PID stays
        # reserved until cleanup, so a reused process group can never be signalled.
        process = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "__poll_supervisor", str(status), *argv],
            stdin=subprocess.PIPE, stdout=output, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        expired = False
        cleanup_error = None
        try:
            end = time.monotonic() + deadline
            while not status.exists():
                remaining = end - time.monotonic()
                if remaining <= 0:
                    expired = True
                    break
                time.sleep(min(0.01, remaining))
        finally:
            # The supervisor is still running (or an unreaped zombie), pinning its
            # PID throughout both signals. Never inspect/reap it before this point.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except OSError as error:
                cleanup_error = error
            time.sleep(0.2)
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except OSError as error:
                cleanup_error = cleanup_error or error
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired as error:
                cleanup_error = cleanup_error or error
            if process.stdin:
                process.stdin.close()
        if cleanup_error is not None:
            raise RuntimeError("poll process group cleanup failed: " + str(cleanup_error))
        if expired:
            raise subprocess.TimeoutExpired(argv, deadline)
        if not status.exists():
            raise RuntimeError("poll supervisor exited without a result")
        output.seek(0)
        return subprocess.CompletedProcess(argv, int(status.read_text()), output.read(65536), "")


def _poll_supervisor(status, argv):
    # A caught handler is reset by exec in the child, while the supervisor stays
    # alive through TERM until its owner finishes the group with KILL.
    signal.signal(signal.SIGTERM, lambda _signum, _frame: None)
    child = subprocess.Popen(argv, stdin=subprocess.DEVNULL)
    code = child.wait()
    Path(status).write_text(str(code))
    sys.stdin.buffer.read()


def _run_poll(event_dir, config, run):
    _atomic_json(event_dir / "status.json", {"state": "polling", "event": config["event"]})
    try:
        deadline = _poll_deadline_seconds(config)
        if run is subprocess.run:
            completed = _run_poll_process(config["poll"], deadline)
        else:
            completed = run(config["poll"], capture_output=True, text=True, timeout=deadline)
        output = "\n".join(part.strip() for part in (completed.stdout, completed.stderr) if part.strip())
        result = {
            "exit_code": completed.returncode,
            "output": output,
            "outcome": _classify_poll(completed.returncode, output),
            "handoff_evidence": _handoff_evidence(config),
            "recorded_at": time.time(),
        }
    except Exception as error:
        result = {
            "exit_code": None,
            "output": type(error).__name__ + ": " + str(error),
            "outcome": "timeout" if isinstance(error, subprocess.TimeoutExpired) else "poll-error",
            "handoff_evidence": _handoff_evidence(config),
            "recorded_at": time.time(),
        }
    _atomic_json(event_dir / "poll-result.json", result)
    return result


def _notification_message(config, poll_result):
    evidence = poll_result["handoff_evidence"]
    if poll_result["outcome"] in ("idle", "done") and evidence == "ready":
        next_step = "Handoff evidence is fresh; inspect it and the current SHA before continuing."
    else:
        next_step = (
            "This needs inspection: resolve the question, blocker, timeout, poll error, or "
            "missing/stale handoff before continuing."
        )
    return (
        "[picsee-listener event {event}] Automated roster status notification. "
        "Task: {task}. Agent: {agent}. Poll outcome: {outcome} (exit {exit_code}). "
        "Expected handoff/report: {handoff}; evidence: {evidence}. {next_step} "
        "Poll completion is not audit acceptance. Continue the delegator workflow only after "
        "checking the pane, report, task identity, and SHA. Do not resend this event after a "
        "queue receipt exists."
    ).format(
        event=config["event"],
        task=config["task"],
        agent=config["agent"],
        outcome=poll_result["outcome"],
        exit_code=poll_result["exit_code"],
        handoff=config["handoff"],
        evidence=evidence,
        next_step=next_step,
    )


def _deliver(event_dir, config, poll_result, run, sleep):
    receipt_path = event_dir / "queue-receipt.json"
    with _locked(event_dir / "delivery.lock"):
        if receipt_path.exists():
            return "already-delivered"
        message = _notification_message(config, poll_result)
        attempts = config.get("max_delivery_attempts", 5)
        initial_backoff = config.get("initial_backoff_seconds", 5)
        errors = []
        for attempt in range(1, attempts + 1):
            _atomic_json(
                event_dir / "status.json",
                {"state": "delivering", "event": config["event"], "attempt": attempt},
            )
            argv = ["codex", "queue", "--thread", config["thread"], "--message", message]
            try:
                completed = run(argv, capture_output=True, text=True, timeout=30)
                if completed.returncode == 0:
                    response = completed.stdout.strip() or completed.stderr.strip()
                    _atomic_json(
                        receipt_path,
                        {
                            "event": config["event"],
                            "task": config["task"],
                            "agent": config["agent"],
                            "thread": config["thread"],
                            "queued_at": time.time(),
                            "attempt": attempt,
                            "queue_response": response,
                        },
                    )
                    _atomic_json(
                        event_dir / "status.json",
                        {"state": "delivered", "event": config["event"], "attempt": attempt},
                    )
                    return "delivered"
                errors.append(completed.stderr.strip() or completed.stdout.strip() or "queue failed")
            except Exception as error:
                errors.append(type(error).__name__ + ": " + str(error))
            if attempt < attempts:
                sleep(min(initial_backoff * (2 ** (attempt - 1)), 300))
        _atomic_json(
            event_dir / "status.json",
            {
                "state": "delivery-failed",
                "event": config["event"],
                "attempts": attempts,
                "last_error": errors[-1],
            },
        )
        raise DeliveryError("queue delivery failed after {} attempts: {}".format(attempts, errors[-1]))


def run_event(event_dir, run=subprocess.run, sleep=time.sleep):
    """Run or reuse the poll result, then deliver one serialized queue notification."""
    event_dir = Path(event_dir)
    config = _read_json(event_dir / "config.json")
    _validate_config(config)
    if (event_dir / "queue-receipt.json").exists():
        return "already-delivered"
    poll_path = event_dir / "poll-result.json"
    poll_result = _read_json(poll_path) if poll_path.exists() else _run_poll(event_dir, config, run)
    return _deliver(event_dir, config, poll_result, run, sleep)


def _pid_is_running(path):
    try:
        pid = int(Path(path).read_text())
        os.kill(pid, 0)
        return True
    except (FileNotFoundError, ProcessLookupError, ValueError):
        return False


def start_listener(event_dir, config, launch=subprocess.Popen):
    """Register and detach one worker without holding a lock during its poll."""
    event_dir = Path(event_dir)
    register_event(event_dir, config)
    with _locked(event_dir / "launch.lock"):
        if (event_dir / "queue-receipt.json").exists():
            return "already-delivered"
        if _pid_is_running(event_dir / "pid"):
            return "already-running"
        _atomic_json(event_dir / "status.json", {"state": "launching", "event": config["event"]})
        log_file = (event_dir / "listener.log").open("a")
        try:
            try:
                process = launch(
                    [sys.executable, str(Path(__file__).resolve()), "run", "--event-dir", str(event_dir)],
                    stdin=subprocess.DEVNULL,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                    close_fds=True,
                )
            except Exception as error:
                _atomic_json(
                    event_dir / "status.json",
                    {"state": "launch-failed", "event": config["event"], "error": str(error)},
                )
                raise
        finally:
            log_file.close()
        (event_dir / "pid").write_text(str(process.pid) + "\n")
        return "started"


def _positive_int(value):
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return parsed


def _build_parser():
    parser = argparse.ArgumentParser(
        description="Detach a shipped picsee roster poller and notify one explicit Codex thread."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    start = subparsers.add_parser("start", help="register and detach a listener")
    start.add_argument("--event", required=True, help="unique ID for this dispatch or fix/audit round")
    start.add_argument("--task", required=True, help="task or round identity shown in the notification")
    start.add_argument("--thread", required=True, help="exact delegator Codex thread UUID")
    start.add_argument("--agent", required=True)
    start.add_argument("--handoff", required=True, help="absolute expected handoff or report path")
    start.add_argument("--poll", required=True, choices=("idle", "handoff", "report"))
    start.add_argument("--interval", type=_positive_int, default=120, help="poll-idle interval seconds")
    start.add_argument("--max-minutes", type=_positive_int, default=600)
    start.add_argument("--handoff-marker", help="fresh round marker required in a handoff")
    start.add_argument("--idle-grace-seconds", type=_positive_int, default=180,
                       help="report mode: time to surface idle without a fresh report")
    start.add_argument("--max-delivery-attempts", type=_positive_int, default=5)
    start.add_argument("--initial-backoff-seconds", type=float, default=5)
    start.add_argument(
        "--state-root",
        type=Path,
        default=Path.home() / ".picsee" / "herdr" / "delegator" / "listeners",
    )
    run = subparsers.add_parser("run", help="internal detached worker")
    run.add_argument("--event-dir", required=True, type=Path)
    return parser


def _config_from_args(args):
    script_dir = Path(__file__).resolve().parent
    handoff = str(Path(args.handoff).expanduser().resolve())
    if args.poll == "idle":
        poll = [str(script_dir / "poll-idle.sh"), args.agent, str(args.interval), str(args.max_minutes)]
    elif args.poll == "handoff":
        poll = [str(script_dir / "poll-handoff.sh"), args.agent, handoff, str(args.max_minutes)]
        if args.handoff_marker:
            poll.append(args.handoff_marker)
    else:
        if args.handoff_marker != args.task:
            raise ValueError("report polling requires --handoff-marker equal to --task")
        config_path = str(args.state_root.expanduser().resolve() / args.event / "config.json")
        poll = [str(script_dir / "poll-report.py"), args.agent, handoff,
                config_path, args.handoff_marker, str(args.interval),
                str(args.max_minutes), str(args.idle_grace_seconds)]
    created_at = time.time()
    return {
        "schema": 1,
        "event": args.event,
        "task": args.task,
        "agent": args.agent,
        "thread": args.thread,
        "handoff": handoff,
        "handoff_marker": args.handoff_marker,
        "poll": poll,
        "poll_deadline_seconds": args.max_minutes * 60 + (args.interval if args.poll in ("idle", "report") else 60) + 10,
        "created_at": created_at,
        "max_delivery_attempts": args.max_delivery_attempts,
        "initial_backoff_seconds": args.initial_backoff_seconds,
    }


def main(argv=None):
    args = _build_parser().parse_args(argv)
    if args.command == "run":
        try:
            print(run_event(args.event_dir), flush=True)
        except Exception as error:
            print(type(error).__name__ + ": " + str(error), file=sys.stderr, flush=True)
            return 1
        return 0
    config = _config_from_args(args)
    event_dir = args.state_root.expanduser().resolve() / args.event
    try:
        result = start_listener(event_dir, config)
    except (EventIdentityError, ValueError) as error:
        print(type(error).__name__ + ": " + str(error), file=sys.stderr)
        return 2
    print(
        "{} event={} state={} status={} receipt={}".format(
            result,
            args.event,
            event_dir,
            event_dir / "status.json",
            event_dir / "queue-receipt.json",
        )
    )
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 3 and sys.argv[1] == "__poll_supervisor":
        _poll_supervisor(sys.argv[2], sys.argv[3:])
    else:
        raise SystemExit(main())
