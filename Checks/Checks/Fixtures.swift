import VentanasCore

/// Test window: what the switcher needs to know about a row.
struct Win: SwitcherItem, Equatable {
    let app: String
    let title: String
    var appID = 0
    var hasWindow = true
    var canQuit = true
    var searchName: String { app }
    var searchTitle: String { title }
}

let chrome = Win(app: "Chrome", title: "Inbox", appID: 1)
let chrome2 = Win(app: "Chrome", title: "Drafts", appID: 1)  // second window of the same app
let iterm = Win(app: "iTerm2", title: "zsh", appID: 2)
let acrobat = Win(app: "Acrobat", title: "Contract", appID: 3)
let mail = Win(app: "Mail", title: "", appID: 4, hasWindow: false)  // app without windows
let finder = Win(app: "Finder", title: "Documents", appID: 5, canQuit: false)
let allWindows = [chrome, iterm, acrobat]
