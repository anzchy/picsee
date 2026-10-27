# #136 smoke-fix test matrix

| WI | Behavior | Lane | Assertion | Spec |
| --- | --- | --- | --- | --- |
| WI-1 | Installed menu receives ⌘I while field editor owns focus | app-red | menu handled, editor remains first responder, caret and `ca` preserved, second toggle then `cat` insertion (L3/L4) | S5 |
| WI-2 | Both localized label sets at 195 and 220 pt in a laid-out native window | swift-red | text is one laid-out line, width ≥ measured glyph width and ≥48 pt, value origin = label width +7 (L3/L4) | S5 |

Adversarial check: routing a key directly to CommandWindow would repeat the old false pass; WI-1 must dispatch through NSApp.mainMenu. Checking only labelWidth constants would repeat the old false pass; WI-2 must inspect laid-out text.
