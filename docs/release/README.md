# Releasing picsee

A release is a tag push. [`.github/workflows/release.yml`](../../.github/workflows/release.yml) builds, signs, notarises and packages picsee. It then opens a **draft** GitHub release and an **appcast pull request**. Nothing reaches users until the owner publishes the draft and merges the PR (spec #212, #222).

## Before the first release

- The secrets wizard has run: `.agents/skills/apple-developer-setup/scripts/setup-secrets-wizard.sh`. That puts these into GitHub Secrets: `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD` and `SPARKLE_ED_PRIVATE_KEY`. It also sets the repository variable `DEVELOPMENT_TEAM`. The workflow reads nothing else. See the [apple-developer-setup skill](../../.agents/skills/apple-developer-setup/SKILL.md).
- `MARKETING_VERSION` in `project.yml` is the version you are releasing (0.0.1).
- The commit to release is on `main`, and CI is green on it.

## Cut a release candidate

```sh
git switch main && git pull
git tag -a v0.0.1-rc.1 -m "picsee 0.0.1 rc.1"
git push origin v0.0.1-rc.1
```

Only `v0.0.1-rc.N` and `v0.0.1` start the workflow. The run fails before building if:
- the tag isn't on `main`;
- the tag's version differs from `MARKETING_VERSION`;
- `DEVELOPMENT_TEAM` is unset.

The build number is the tag commit's commit count (`git rev-list --count`), so builds increase with `main`.

## What the run does

1. **Release build:**
   - Signed with the team's Developer ID Application certificate, from a temporary keychain that is deleted at the end of every run.
   - Hardened runtime on.
   - `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`, so there is no `get-task-allow`.
   - Stripped, so the binary carries no build-machine paths.
2. Sparkle 2.10.0's `LICENSE` is copied to `Contents/Resources/ThirdPartyNotices/Sparkle-2.10.0-LICENSE.txt`. It comes from the release tools tarball pinned by SHA-256 and includes Sparkle's external licences.
3. **Re-signing:** Sparkle's helpers are re-signed with Developer ID in the order Sparkle's sandboxing documentation gives: Installer.xpc, Downloader.xpc, Autoupdate, Updater.app, then the framework. The app is signed last, followed by `codesign --verify --deep --strict`.
4. **Checks on the signed app, before anything is sent to Apple:**
   - `node scripts/release/check-entitlements.mjs <app> --configuration release`: exactly ADR-015's five entitlements.
   - `node scripts/release/check-package.mjs <app> --require-sparkle-licence --expect-version … --expect-build …`. It fails on research, prototype or evidence files, credentials, private photos, scripts, documents or build paths. It also checks that the Sparkle Info.plist keys keep the second-launch question and send no system profile, that the version and build are right, and that the licence is present.
5. **App notarisation:** the app is notarised (`notarytool submit --wait`, Apple ID with an app-specific password), stapled and validated.
6. **DMG:**
   - The DMG holds the stapled app and an Applications link (`hdiutil`, APFS, lzfse).
   - It is signed, notarised, stapled and validated.
   - `spctl` assesses both the DMG and the app.
7. **Draft release** `v0.0.1-rc.N`:
   - Assets: `Picsee-0.0.1.dmg` and `Picsee-0.0.1.dmg.sha256`.
   - Notes from [`notes-template.md`](notes-template.md): checksum, privacy statement, a placeholder for what's new.
   - rc tags are marked pre-release.
8. **Appcast PR:**
   - The DMG is signed with Sparkle's EdDSA key, which reaches `sign_update` only on standard input.
   - `scripts/release/appcast.mjs` adds the item to `appcast.xml` on a new branch `appcast/<tag>`.
   - A PR to `main` is opened.

To check a local build before tagging (unsigned, so skip the licence and entitlement checks):

```sh
xcodebuild build -scheme Picsee -configuration Release CODE_SIGNING_ALLOWED=NO \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES -derivedDataPath .build/dd-rel
node scripts/release/check-package.mjs .build/dd-rel/Build/Products/Release/Picsee.app
```

## What the owner does

1. **Check the draft on the MacBook test user:**
   - Download the DMG from the draft release.
   - Check `shasum -a 256` against the notes.
   - Open the DMG, drag picsee into Applications and launch it. Gatekeeper must not warn.
   - Edit the notes' "What is in this version".
2. **Publish the draft.** The appcast's enclosure URL only works once the release is public.
3. **Merge the appcast PR** after publishing. Installed copies see the update as soon as `appcast.xml` lands on `main`; that is the feed in `SUFeedURL`.
4. **Promote to final:** when an rc is good, tag `v0.0.1` on the same or a later `main` commit and repeat.

The appcast PR is opened with the workflow's token, so GitHub does not run CI on it. It changes only `appcast.xml`.

## When a run fails

The run stops at the first failing step and always deletes its keychain. Fix the cause on `main`, then do one of:
- delete the tag (`git push --delete origin v0.0.1-rc.N`) and any draft it made, and re-tag;
- or cut `rc.N+1`.

Never edit a published release's DMG: Sparkle verifies the EdDSA signature in the appcast against it.
