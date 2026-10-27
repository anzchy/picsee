---
status: proposed
date: 2026-10-27
---

# ADR-012: UI test fixtures enter through the App container

## Decision

The small local/nightly XCUITest set may launch a **test-compiled** Picsee with `-PicseeUITestFixture <name>`. The test sends three pinned `TestAssets` image bytes in launch environment variables. The App writes them to a uniquely named directory under its own `Application Support/Picsee/UITestFixtures`, then uses the existing `CanvasWindowController.openGrantedFolder` → folder scan → Grid presentation route. The fixture name permits only ASCII letters, digits and `-`; it cannot name a path or follow a supplied symlink. The adapter and its separate bookmark/recent stores exist only when both `DEBUG` and `PICSEE_UI_TEST_FIXTURE` are set. An ordinary Debug or any Release build omits the active adapter and ignores the argument, even if a Release build is passed the test flag.

The isolated test adapter treats readable files **inside that fixture directory** as a local root. It does not obtain a user grant or extend the OS sandbox. It keeps its synthetic bookmark records inside the unique fixture directory; they are not production Access Roots and are not evidence for the security-scoped grant or bookmark path in ADR-008. The production entitlements and Info.plist do not change. The normal system access adapter remains the only production path.

This is a smoke probe to see whether the real signed, sandboxed App can show the completed Grid through the ordinary scan/presentation code after fixture staging. Only the delegator runs it under the GUI lock. Until that result arrives, the probe is **pending**, not a verified Grid claim. If the probe fails because the container or AX behavior differs from this design, record the failure here and keep XCUITest to the reachable keyboard/focus, menu-enable and accessibility-audit checks; user grants, bookmark persistence and panel behavior remain signed device checks.

The UI test uses `XCUIApplication()` with `PicseeApp` set as its Target Application (`TEST_TARGET_NAME`), so Xcode launches the product built for that test run. A bundle-ID lookup is forbidden here: LaunchServices can select another registered `io.github.anzchy.picsee` copy, including the user's installed App. Before checking the Grid, the test waits for the unique fixture name at `grid.sidebar.folder`; a flag-off or wrong build then fails with an explicit fixture-entry message. The first proposed probe was aborted before launch when this risk was found.

## Options considered

| Option | Sandbox authority and entitlement | Release risk | What it covers and misses |
|---|---|---|---|
| Launch argument naming `TestAssets` directly | A path is not a Powerbox grant. `FileAccess.grant` requires a successfully started security scope, so this cannot lawfully open an external folder without a pre-grant. No entitlement is added. | A generic argument parser could leak; rejected. | Would exercise the full folder path only if authority somehow existed; cannot prove a grant by naming a path. |
| Copy a fixture into the App container, then use a bounded test-only launch hook (**chosen**) | [Apple documents](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) the App's unrestricted access to its own container. The local adapter changes no OS authority, entitlement or production access behavior. | Hook is behind an explicit compile flag absent from normal Debug and Release builds. Flag-off unit assertion checks the argument is ignored. | Exercises fixture staging, folder scan, Grid rendering and AX item count. Does not cover Powerbox, real security scopes, production bookmarks, grant/reconnect, external folders or persistence. |
| Drive `NSOpenPanel`/Powerbox with XCUITest | A real selection would grant the external folder; no entitlement change. | No code hook. | Covers a particular panel interaction, but is fragile and explicitly excluded by #130's small XCUITest decision. |
| Preseed a bookmark, use an absolute launch path, or add a temporary exception | A bookmark from another process is not a user grant for this App; an exception or pre-grant would change the authorization boundary. | Can contaminate Release settings and production data. | Would obscure the very sandbox behavior the test is meant to respect; rejected. |

Apple's [sandbox file-access guide](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) describes the grant supplied by the system panel and security-scoped bookmarks. A URL passed as a string has no such grant. The existing `ScopeSession` also rejects a root when `startAccessingSecurityScopedResource()` fails, which is why merely copying the fixture into the container is insufficient for the current `FileAccess.grant` contract.

## Probe and interpretation

From this worktree, the delegator runs this **one command** on the Mac mini under the shared GUI lock (it builds and executes the single UI test):

```sh
scripts/heavy-lock.sh xcodebuild test -scheme PicseeFixtureUI -only-testing:PicseeUITests/PicseeFixtureGridUITests/testContainerFixtureOpensThreeImageGrid -destination 'platform=macOS' SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) PICSEE_UI_TEST_FIXTURE' -derivedDataPath .build/dd-issue132-probe
```

The expected observation is `grid.collection` containing exactly three `grid.cell` descendants after the scan completes. A passing probe establishes only that the test build can stage those images in its sandbox container and reach the Grid. It does not validate production user authorization or bookmark behavior. The UI test is local/nightly and outside PR gates and Swift package coverage.

## Consequences

- The UI test target packages only three small synthetic files from `TestAssets`; no `TestAssets`, HTML, research material or test adapter is added to the production App bundle.
- This fixture build has the same bundle ID and team as the developer's installed Picsee. It shares that App container, thumbnail cache and preferences. The test hook keeps synthetic access records in only its unique fixture subfolder. At test teardown, `app.terminate()` invokes test-only App cleanup; the test also attempts `FileManager` removal of that exact run folder as a fallback. Neither path deletes the container or another run's folder. A forced process kill or denied test-runner container access may leave the one run folder for later manual inspection.
- A11Y-01 and CMD-01 do not advance from this harness or its unsigned build. Their native/VoiceOver and keyboard claims still require the specified device observations.
