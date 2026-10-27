# TDD Review — APPROVED WITH NOTES

Timestamp: 2026-10-27T06:29:56Z
Scope: F4 direct search Inspector synchronization, N1 footer/Inspector Tab order and search caret, package and App tests, ledger rows.

## Findings

No remaining code or test-quality blocker. The App bundle passes D→A→empty→D without a window update and checks the actual first responder through the full forward and reverse key loop. The package tests assert Inspector model values and visible footer targets, not callback wiring alone. No internal module mock, security mock assertion, coverage-ignore directive, or acceptance weakening was added.

## Receipt note

`issue136-COMBO2-WI-1` is marked `SEPARATION-BROKEN` because the package test's clear-search expectation changed after valid RED. Its original A expectation was wrong: the brief requires the restored Current Item, and the pre-fix combined App RED run established that clearing restores D. The corrected D assertion and the independent App D→A→empty→D test both pass. The recorded RED was an assertion failure against the old behavior; the only pre-RED production edits were compileable API stubs. `issue136-COMBO2-WI-2` is `SEPARATION-HELD`; both receipts retain the plugin's standard MEDIUM note for uncommitted compileable stubs.

## Residual limits

The seven App bundle tests run offscreen through `xcrun xctest`; signed device and GUI verification are outside the brief. Package LCOV excludes App target code. No PR or push was requested.
