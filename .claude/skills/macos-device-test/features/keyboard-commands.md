# Keyboard and command routing

The basic commands do the same thing whether triggered from the menu, a button or the keyboard; a text field
or an open menu gets its keys first; and the core path can be done without the mouse with focus always
visible.

## Sub-features

- `CMD-01` Space, ←/→, Esc, Enter, 0/1, +/−, ⌘F, ⌘O, ⌘I trigger the same action from menu, button and key;
  unimplemented commands show no shortcut.
- `CMD-02` in the search field, Space and ← edit text instead of flipping images; with a menu open, Esc only
  closes the menu.
- `A11Y-02` open a folder, select an image, view it, go back and open the Inspector without the mouse, with
  focus always visible.

## How to get to it (user POV)

- Each command's menu item.
- Each command's button, where one exists.
- Each command's keyboard shortcut.
- The search field (⌘F) and any open menu.

## Driving it with computer use

Preconditions:

- A granted fixture folder with at least five images (see open-and-grant.md).
- Input source ABC.

- **Same action, three ways.** For each command in CMD-01, trigger it from the menu, then the button (if any),
  then the key, from the same starting state. Each gives the same resulting state. One verdict line per
  command and entry point.
- **No false hints.** Open each menu. Commands not yet implemented show no shortcut.
- **Field priority.** Press ⌘F, type `a b`, press ←. The field contains `a b` with the caret moved; the image
  didn't change.
- **Menu priority.** Open a menu, press Esc. The menu closes and the viewer stays as it was.
- **Keyboard only.** Without touching the mouse, open the folder, select an image, view it, return, open the
  Inspector. A focus ring is visible at every step.
- **Proof.** `CMD-01-<command>-<entry>.png` where the state is visual, `CMD-02-field.png`, and a short
  screenshot sequence for A11Y-02.

## Gotchas

- Esc through computer use may not reach a native app as a key-down (unverified); check the log, and if it
  doesn't arrive, make Esc a user step.
- A menu-bar utility can block clicks in the menu bar; use the key for the command and record the menu entry
  point as NOT VERIFIED.
- Space in the grid and Space in the viewer are different commands; start each check from the stated view.
