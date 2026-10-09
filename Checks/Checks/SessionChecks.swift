import VentanasCore

private final class Requests {
    var scopes: [Scope] = []
}

private func makeSession(
    trigger: Modifier = .command, windows: [Win] = allWindows, requests: Requests = Requests()
) -> SwitcherSession<Win> {
    SwitcherSession(trigger: { trigger }, listWindows: { scope in
        requests.scopes.append(scope)
        return windows
    })
}

private extension SwitcherSession where Item == Win {
    @discardableResult func press(_ key: Key, _ modifiers: Modifiers = .command) -> Outcome<Win> {
        handle(.key(key, modifiers))
    }

    /// ⌘⇧W / ⌘⇧Q: the keyboard shortcuts to close a window / quit an app.
    func chord(_ text: String, _ modifiers: Modifiers = [.command, .shift]) -> Outcome<Win> {
        press(.character(text), modifiers)
    }

    /// ⌘Tab: opens the session (window 1 gets selected).
    @discardableResult func open() -> Outcome<Win> { press(.tab) }
}

private func expect(_ name: String, _ outcome: Outcome<Win>, swallow: Bool, _ effects: [Effect<Win>]) {
    check(name, outcome == Outcome(swallow: swallow, effects: effects), "obtenido: \(outcome)")
}

func sessionChecks() {
    let all = allWindows

    // MARK: opening
    do {
        let s = makeSession()
        expect("⌘Tab opens the panel with the next window selected",
               s.open(), swallow: true, [.show(items: all, query: "", selection: 1)])
    }
    do {
        let s = makeSession()
        expect("⌘⇧Tab opens with the last one selected",
               s.press(.tab, [.command, .shift]), swallow: true, [.show(items: all, query: "", selection: 2)])
    }
    do {
        let requests = Requests()
        makeSession(requests: requests).open()
        makeSession(requests: requests).press(.sameAppKey)
        check("⌘Tab asks for all windows and ⌘` only for the current app's",
              requests.scopes == [.allWindows, .currentApp], "\(requests.scopes)")
    }
    do {
        expect("with a single window, 0 is selected",
               makeSession(windows: [chrome]).open(), swallow: true, [.show(items: [chrome], query: "", selection: 0)])
    }
    do {
        let s = makeSession(windows: [])
        expect("with no windows the key is swallowed and nothing opens", s.open(), swallow: true, [])
        expect("and the session does not become active", s.press(.escape), swallow: false, [])
    }

    // MARK: visible state
    do {
        let s = makeSession()
        check("without a session it is not active", !s.isActive)
        s.open()
        check("after ⌘Tab it is active", s.isActive)
        s.handle(.dismiss)
        check("after closing it is no longer active", !s.isActive)
    }

    // MARK: what does not open
    do {
        let s = makeSession()
        expect("Tab without a modifier goes to the app", s.press(.tab, []), swallow: false, [])
        expect("⌘W goes to the app", s.press(.character("w")), swallow: false, [])
        expect("⌘⌥Tab does not open (another modifier is held)", s.press(.tab, [.command, .option]), swallow: false, [])
        expect("changing modifiers without a session does nothing", s.handle(.modifiersChanged([])), swallow: false, [])
        expect("a click without a session does nothing", s.handle(.pick(0)), swallow: false, [])
        expect("a click outside without a session does nothing", s.handle(.dismiss), swallow: false, [])
    }
    do {
        let s = makeSession(trigger: .option)
        expect("with ⌥ as the shortcut, ⌘Tab does not open", s.press(.tab, .command), swallow: false, [])
        expect("with ⌥ as the shortcut, ⌥Tab opens",
               s.press(.tab, .option), swallow: true, [.show(items: all, query: "", selection: 1)])
    }

    // MARK: navigating
    do {
        let s = makeSession()
        s.open()
        expect("Tab moves forward", s.press(.tab), swallow: true, [.select(2)])
        expect("Tab wraps around at the end", s.press(.tab), swallow: true, [.select(0)])
        expect("⇧Tab moves back, wrapping around", s.press(.tab, [.command, .shift]), swallow: true, [.select(2)])
        expect("down arrow moves forward", s.press(.down), swallow: true, [.select(0)])
        expect("up arrow moves back", s.press(.up), swallow: true, [.select(2)])
        expect("right arrow moves forward", s.press(.right), swallow: true, [.select(0)])
        expect("left arrow moves back", s.press(.left), swallow: true, [.select(2)])
        expect("⌘` also navigates", s.press(.sameAppKey), swallow: true, [.select(0)])
    }

    // MARK: switching or cancelling
    do {
        let s = makeSession()
        s.open()
        expect("pressing ⇧ while ⌘ is still held does not switch", s.handle(.modifiersChanged([.command, .shift])), swallow: false, [])
        expect("releasing the modifier switches to the selected window",
               s.handle(.modifiersChanged([])), swallow: false, [.hide, .focus(iterm)])
        expect("after switching, the session ends", s.press(.tab, []), swallow: false, [])
    }
    do {
        let s = makeSession()
        s.open()
        expect("releasing the modifier also switches even if ⇧ is still held",
               s.handle(.modifiersChanged([.shift])), swallow: false, [.hide, .focus(iterm)])
    }
    do {
        let s = makeSession()
        s.open()
        expect("Return switches to the selected window", s.press(.confirm), swallow: true, [.hide, .focus(iterm)])
    }
    do {
        let s = makeSession()
        s.open()
        expect("Esc closes without switching", s.press(.escape), swallow: true, [.hide])
        expect("and releasing the modifier afterwards does nothing", s.handle(.modifiersChanged([])), swallow: false, [])
    }

    // MARK: search
    do {
        let s = makeSession()
        s.open()
        expect("typing filters and selects the first one",
               s.press(.character("a")), swallow: true, [.show(items: [acrobat], query: "a", selection: 0)])
        expect("typing more accumulates the query",
               s.press(.character("c")), swallow: true, [.show(items: [acrobat], query: "ac", selection: 0)])
        expect("releasing the modifier while searching does not close", s.handle(.modifiersChanged([])), swallow: false, [])
        expect("Return switches to the filtered window", s.press(.confirm, []), swallow: true, [.hide, .focus(acrobat)])
    }
    do {
        let s = makeSession()
        s.open()
        s.press(.tab)
        expect("typing resets the selection to the first filtered one",
               s.press(.character("i")), swallow: true, [.show(items: [chrome, iterm], query: "i", selection: 0)])
    }
    do {
        let s = makeSession()
        s.open()
        s.press(.character("a"))
        s.press(.character("c"))
        expect("delete removes the last letter",
               s.press(.delete), swallow: true, [.show(items: [acrobat], query: "a", selection: 0)])
        expect("deleting the last letter shows all windows again",
               s.press(.delete), swallow: true, [.show(items: all, query: "", selection: 0)])
        expect("delete with an empty query does nothing", s.press(.delete), swallow: true, [])
        expect("with an empty query after deleting, it stays open on release",
               s.handle(.modifiersChanged([])), swallow: false, [])
    }
    do {
        let s = makeSession()
        s.open()
        expect("with no results an empty list is shown",
               s.press(.character("q")), swallow: true, [.show(items: [], query: "q", selection: 0)])
        expect("Return with no results only closes", s.press(.confirm), swallow: true, [.hide])
    }
    do {
        let s = makeSession()
        s.open()
        expect("a key that is not text is swallowed and does nothing",
               s.press(.character("\u{F704}")), swallow: true, [])
        expect("space counts as text",
               s.press(.character(" ")), swallow: true, [.show(items: [], query: " ", selection: 0)])
    }

    // MARK: mouse
    do {
        let s = makeSession()
        s.open()
        expect("a click on a row switches to that window", s.handle(.pick(2)), swallow: false, [.hide, .focus(acrobat)])
    }
    do {
        let s = makeSession()
        s.open()
        s.press(.character("a"))
        expect("the click uses the index in the filtered list", s.handle(.pick(0)), swallow: false, [.hide, .focus(acrobat)])
    }
    do {
        let s = makeSession()
        s.open()
        expect("a click on a nonexistent row only closes", s.handle(.pick(9)), swallow: false, [.hide])
    }
    do {
        let s = makeSession()
        s.open()
        expect("a click outside closes without switching", s.handle(.dismiss), swallow: false, [.hide])
        expect("and the session ends", s.press(.tab, []), swallow: false, [])
    }

    // MARK: closing windows and quitting apps (keyboard)
    do {
        let s = makeSession()
        s.open()  // iTerm selected
        expect("⌘⇧W closes the selected window and drops its row",
               s.chord("W"), swallow: true, [.closeWindow(iterm), .show(items: [chrome, acrobat], query: "", selection: 1)])
        expect("Return then switches to the row that took its place",
               s.press(.confirm), swallow: true, [.hide, .focus(acrobat)])
    }
    do {
        let s = makeSession()
        s.open()
        s.press(.tab)  // Acrobat selected, the last row
        expect("closing the last row moves the selection up (lowercase w works too)",
               s.chord("w"), swallow: true, [.closeWindow(acrobat), .show(items: [chrome, iterm], query: "", selection: 1)])
    }
    do {
        let s = makeSession(windows: [chrome, chrome2, iterm, acrobat])
        s.open()  // the second Chrome window selected
        expect("⌘⇧Q quits the app and drops every row of it",
               s.chord("Q"), swallow: true, [.quitApp(chrome2), .show(items: [iterm, acrobat], query: "", selection: 0)])
    }
    do {
        let s = makeSession(windows: [chrome])
        s.open()
        expect("closing the only window ends the session",
               s.chord("W"), swallow: true, [.closeWindow(chrome), .hide])
        check("and the session is no longer active", !s.isActive)
    }
    do {
        let s = makeSession(windows: [chrome, chrome2])
        s.open()
        expect("quitting the only app ends the session",
               s.chord("Q"), swallow: true, [.quitApp(chrome2), .hide])
        check("and the session is no longer active after quitting", !s.isActive)
    }

    // MARK: closing windows and quitting apps (buttons)
    do {
        let s = makeSession()
        s.open()  // iTerm selected (row 1)
        expect("closing a row above the selection keeps the same window selected",
               s.handle(.closeWindow(0)), swallow: false,
               [.closeWindow(chrome), .show(items: [iterm, acrobat], query: "", selection: 0)])
    }
    do {
        let s = makeSession()
        s.open()
        expect("closing a row below the selection leaves the selection alone",
               s.handle(.closeWindow(2)), swallow: false,
               [.closeWindow(acrobat), .show(items: [chrome, iterm], query: "", selection: 1)])
    }
    do {
        let s = makeSession()
        s.open()
        expect("closing the selected row selects the one that follows",
               s.handle(.closeWindow(1)), swallow: false,
               [.closeWindow(iterm), .show(items: [chrome, acrobat], query: "", selection: 1)])
    }
    do {
        let s = makeSession()
        s.open()
        expect("quitting a row below the selection leaves the selection alone",
               s.handle(.quitApp(2)), swallow: false,
               [.quitApp(acrobat), .show(items: [chrome, iterm], query: "", selection: 1)])
    }
    do {
        let s = makeSession(windows: [chrome, chrome2, iterm])
        s.open()  // the second Chrome window selected
        expect("quitting the app of the selected row selects the next surviving row",
               s.handle(.quitApp(0)), swallow: false,
               [.quitApp(chrome), .show(items: [iterm], query: "", selection: 0)])
    }
    do {
        let s = makeSession()
        s.open()
        expect("a button on a row that doesn't exist does nothing", s.handle(.closeWindow(9)), swallow: false, [])
        expect("the same goes for quit", s.handle(.quitApp(9)), swallow: false, [])
    }
    do {
        let s = makeSession()
        expect("a close button click without a session does nothing", s.handle(.closeWindow(0)), swallow: false, [])
        expect("a quit button click without a session does nothing", s.handle(.quitApp(0)), swallow: false, [])
    }

    // MARK: rows without windows, and the Finder
    do {
        let s = makeSession(windows: [chrome, mail])
        s.open()  // Mail selected
        expect("closing a row without a window does nothing", s.chord("W"), swallow: true, [])
        expect("its close button does nothing either", s.handle(.closeWindow(1)), swallow: false, [])
        expect("but its app can be quit",
               s.chord("Q"), swallow: true, [.quitApp(mail), .show(items: [chrome], query: "", selection: 0)])
    }
    do {
        let s = makeSession(windows: [chrome, finder])
        s.open()  // Finder selected
        expect("the Finder can't be quit", s.chord("Q"), swallow: true, [])
        expect("its quit button does nothing", s.handle(.quitApp(1)), swallow: false, [])
        expect("but its window can be closed",
               s.chord("W"), swallow: true, [.closeWindow(finder), .show(items: [chrome], query: "", selection: 0)])
    }

    // MARK: the shortcuts and the search
    do {
        let s = makeSession()
        s.open()
        expect("a plain w is still search", s.press(.character("w")), swallow: true, [.show(items: [], query: "w", selection: 0)])
    }
    do {
        let s = makeSession()
        s.open()
        s.press(.character("c"))
        s.handle(.modifiersChanged([]))  // modifier released: the session stays open while searching
        expect("without the trigger modifier, ⇧W is text",
               s.press(.character("W"), [.shift]), swallow: true, [.show(items: [], query: "cW", selection: 0)])
    }
    do {
        let s = makeSession()
        s.open()
        s.press(.character("a"))
        s.press(.character("c"))  // only Acrobat matches
        expect("⌘⇧W closes the window found by the search",
               s.chord("W"), swallow: true, [.closeWindow(acrobat), .show(items: [], query: "ac", selection: 0)])
    }
    do {
        let s = makeSession(windows: [chrome, chrome2, iterm, acrobat])
        s.open()
        for letter in ["i", "n", "b"] { s.press(.character(letter)) }  // only the first Chrome window matches
        expect("quitting from a search also drops the app's rows the search hid",
               s.chord("Q"), swallow: true, [.quitApp(chrome), .show(items: [], query: "inb", selection: 0)])
        s.press(.delete)
        s.press(.delete)
        expect("clearing the search shows what is left",
               s.press(.delete), swallow: true, [.show(items: [iterm, acrobat], query: "", selection: 0)])
    }
}
