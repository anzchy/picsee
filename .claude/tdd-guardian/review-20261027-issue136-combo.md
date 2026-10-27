# TDD Review — APPROVED WITH NOTES

Scope: #136 combination changes in App, PicseeApplication, PicseeMacUI, package tests, AppTests, and feature ledger.

## Findings

No code or test-quality blocker found. Changed tests assert the observed first responder, search text, Inspector model name, window focus state, Escape policy output, and rendered footer frames. No wiring-only assertions, internal-module mocks, security mock assertions, or coverage ignore directives were added. The watched-refresh tests cover the invariant that Inspector Current Item follows the reconciled session, including the empty result. No additional property law applies to key routing or layout.

## Notes

The F1 RED assertion stayed unchanged, but its initial offscreen `NSHostingView` fixture was removed after RED because it crashed the full SwiftPM suite when combined with other AppKit tests. The final package test checks the focus decision; `issue136CombinedWindowSearchFocusEscapeAndInspectorToggle` in the App test bundle checks the actual window behavior. The receipt CLI reports SEPARATION-HELD because the recorded assertion line was retained.

`xcodebuild test` compiled the App test bundle but its wrapper could not instantiate it. Running the same compiled bundle directly with `xcrun xctest` passed all five tests. No signed device run was performed, as the brief forbids launching or driving the App.
