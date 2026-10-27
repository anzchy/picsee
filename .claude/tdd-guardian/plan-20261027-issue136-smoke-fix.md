# #136 signed-smoke repair

### WI-1: Preserve grid search across the actual Inspector menu key equivalent
- AC: With grid.search.field editing `ca` at offset 2, a real ⌘I menu equivalent opens and closes Inspector without moving first responder or changing selection.
- AC: The next inserted `t` makes `cat`.
- Test: App window with installed CommandMenu and NSApp.mainMenu performKeyEquivalent; assertion RED before code.
- Receipt: issue136-SMOKE-WI-1 via manual App RED lane.

### WI-2: Size Inspector label column to localized text
- AC: At 195 and 220 pt panels in en and zh-Hans, each laid-out label is one line and at least its actual-font measured width, minimum 48 pt.
- AC: Value starts 7 pt after label column and may wrap.
- Test: laid-out NSHostingView in NSWindow, actual row text layout plus column measurements; assertion RED before code.
- Receipt: issue136-SMOKE-WI-2 via swift-red.
