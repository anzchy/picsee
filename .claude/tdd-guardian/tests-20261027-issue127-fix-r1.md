# Test matrix — #127 fix round 1

| WI | Test | Level and assertion | Failure mode |
|---|---|---|---|
| WI-1 | Real temporary Git repository, deletion-only UI diff via CLI | integration, output (Level 1), S3 | `--diff-filter` omitted D |
| WI-1 | Same CLI with a state table, missing/invalid/valid `Device-Smoke:`; non-App `n/a` | integration, output (Level 1), S2/S3 | stale per-PR parity rule or missing smoke line |
| WI-2 | Incomplete scan, explicit late `.jpeg`, earlier `.jpg`, JPG filter | unit, state and side effect (Levels 2/4), S5 across batches | raw extension comparison jumps current or shows no-match |
| WI-3 | Cleanup with a PID file but no process identity record | unit at OS boundary, no signal and retired record (Levels 2/4), S3 | killing a process this run did not start |

Adversarial check: the UI test uses real `git diff` rather than a supplied file list; the scan test exercises the coordinator and presentation host rather than only `FolderSnapshot.applying`; the cleanup test checks the signal boundary. No additional user-visible behavior is in scope.
