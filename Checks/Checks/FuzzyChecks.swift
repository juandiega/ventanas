import VentanasCore

func fuzzyChecks() {
    let all = allWindows
    check("an empty query keeps the order", Fuzzy.filter(all, query: "") == all)

    let gmail = Win(app: "Gmail", title: "")
    let mail = Win(app: "Mail", title: "")
    check("a prefix match beats a plain contains",
          Fuzzy.filter([gmail, mail], query: "mai") == [mail, gmail])

    check("ignores case and accents",
          Fuzzy.filter([Win(app: "Café", title: "")], query: "CAFE").count == 1)

    check("accepts subsequences", Fuzzy.filter([chrome], query: "crm") == [chrome])
    check("also searches the title", Fuzzy.filter(all, query: "contract") == [acrobat])
    check("excludes what doesn't match", Fuzzy.filter(all, query: "q").isEmpty)
}
