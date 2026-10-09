// No XCTest (the Command Line Tools don't ship it): each check prints ok/FAIL and is counted;
// `main.swift` exits with code 1 if any of them fails.
var failures = 0

func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    print(condition ? "ok   " : "FAIL ", name, condition ? "" : detail())
    if !condition { failures += 1 }
}
