# Codex worktree roles

`picsee.rules` contains shared safety restrictions. Codex prefix rules cannot inspect the
agent role from the prompt. The local ignored `picsee-role.rules` adds push/PR bans for
implementors and auditors. The delegator overlay is empty except for its role declaration;
it does not override a forbidden rule. Release/workflow, destructive, sandbox and other
pre-existing restrictions remain in the common file.

Before starting Codex in **every** new worktree:

```sh
python3 scripts/codex-rules/install-role.py --worktree /absolute/worktree --role implementor
```

Use `auditor` for audit worktrees. Omitted role defaults to implementor. Only the appointed
delegator may be provisioned with `--role delegator`, under explicit user authorization.
Missing overlay means incomplete provisioning; do not launch agents until installed.
This is orchestration-enforced provisioning, not automatic role detection or a security
boundary against an agent editing its own rules. Existing AGENTS.md ownership rules apply.

The installer writes atomically, rejects unknown roles and a symlink target, and never
changes common rules. An old worktree with common unconditional push bans remains restricted
until it updates to the common rules split. A new allow entry cannot override an existing
forbidden match. Install restricted overlays before distributing the new common file.

Run `npm run rules:check`: commands are passed as data to `codex execpolicy check`, never
executed. Tests compose both common and role rules. Rules match argv prefixes only; retain
the documented limitations of the original rules. Existing sessions may cache their loaded
rules. After an authorized change, test a normal `git push --dry-run`; if still rejected,
restart the delegator session with the same worktree. Do not bypass using alternate argv.
