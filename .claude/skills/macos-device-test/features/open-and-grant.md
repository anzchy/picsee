# Open and grant a folder

Opening one image from Finder gives Picsee a File Grant for that file only. Moving on to the next image asks
the user to grant the folder, which then becomes an Access Root that survives relaunch, and the access is
released when the window that used it closes.

## Sub-features

- `ACCESS-01` after opening a single file, → asks to grant its folder instead of failing silently.
- `ACCESS-02` a granted folder can be browsed after quitting and relaunching, with no new prompt.
- `ACCESS-05` closing the window releases the folder access.

## How to get to it (user POV)

- Open a JPEG from Finder (or `open -a` with the file, which is the same File Grant).
- Press → in the viewer.
- Grant the folder in the system open panel that the prompt leads to.
- Quit Picsee and open it again, then open an image in that folder (or its Recent Item).
- Close the window.

## Driving it with computer use

Preconditions:

- Sandbox container **fresh** (deleted with the user's approval, recorded), so no Access Root exists yet.
- Fixture folder: a copy of S1 in `$RUN_DIR/fixtures/S1/`, with at least three images.

- **File Grant.** Launch with one image from the fixture folder. The image is shown.
- **Ask to grant.** Press →. A prompt explains that browsing the folder needs permission and offers to grant
  it. Nothing else changes; the current image stays.
- **Grant.** Accept, and choose the fixture folder in the open panel. The next image is shown.
- **Relaunch.** Quit Picsee (⌘Q), relaunch by absolute path with no file, and open the same folder's Recent
  Item. The folder is browsable and no open panel appears.
- **Release.** Close the window. The log shows the folder's access being released (the log line is defined in
  P0-04 and recorded here).
- **Proof.** `ACCESS-01-arrow-prompt.png`, `ACCESS-02-relaunch-browsing.png`, and the log excerpt with the
  release line, from `app.log`.

## Gotchas

- Launching with a file routes into a running instance unless none is running; doctor first.
- Whether a bookmark survives a **rebuild** (a new signature) is unverified. Relaunch the same bundle, and
  record which build created and which resolved the bookmark.
- Never pre-grant the folder by hand or copy files into the container; the open panel is the path under test.
- Granting the folder must not add it to the Library: it shows under Recent only.
