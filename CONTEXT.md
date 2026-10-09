# Ventanas: glossary

The project's domain language. Use these terms as written in code, tests, issues and commits.

**Switcher**: the floating panel with the list of windows. It is what you see, not the logic that drives it.

**Session**: the time from pressing the shortcut until the modifier is released or the switcher is cancelled.
A session always ends in one of two ways: it switches to a window, or it closes without switching (Esc, click
outside).
_Avoid_: "mode", "switcher state".

**Trigger modifier**: the key held down to open the switcher (⌘, ⌥ or ⌃, configurable in Settings). With ⌘ it
replaces the system ⌘Tab.
_Avoid_: "shortcut" when only the modifier key is meant; the shortcut is the modifier plus Tab.

**Current window**: the focused window of the frontmost app. It is **not** the first window in the list that
macOS returns: floating windows (Picture-in-Picture) always come first without being the ones you use.
Mixing the two up was the bug that made the first Tab "do nothing".
_Avoid_: "first window", "top window".

**Selected window**: the highlighted row in the switcher, the one that gets focus on release. In a new session
it is the window after the current one (with ⇧: the last one).

**Row actions**: closing a window or quitting an app straight from the switcher, with the buttons on a row or
with the trigger modifier plus ⇧ plus W / Q. Closing a window drops only its row; quitting an app drops every row
of that app. Either way the session stays open, unless nothing is left. They are fire and forget: if the app
asks to save changes first, the row is already gone and comes back in the next session. A row without a window
has nothing to close, and the Finder can't be quit.

**Search**: filtering the list by typing while the session is open. After typing, the session no longer closes
when the modifier is released and waits for Return or Esc.

**Switcher order**: the list comes in three groups. First the visible windows, with the current window at the
front and floating ones after the normal ones. Then the non-visible windows. Finally the apps without windows
(only with the all-windows shortcut, not with the current-app one). Ties keep the input order.

**Non-visible window**: a window that is not on screen (minimized, from a hidden app, or with an ID that could
not be read). It goes after the visible ones, ordered by how recently its app was used and then by its position
within that app.
