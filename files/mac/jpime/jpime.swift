// jpime: toggle the Japanese (Kotoeri) input method on macOS.
//
// Enabled  -> select ABC, then disable every Kotoeri input source so the
//             input menu goes back to Chinese + English only.
// Disabled -> enable Kotoeri Romaji typing with its Japanese (Hiragana) mode
//             and select it.
//
// Compiled by targets/mac/modules/jpime.nix with the system swiftc; invoked
// by Karabiner on ⌃⌥J (files/mac/karabiner/karabiner.json).

import Carbon
import Foundation

let englishID = "com.apple.keylayout.ABC"
let kotoeriPrefix = "com.apple.inputmethod.Kotoeri"
// What "Japanese on" means. The parent input method must be enabled before
// its mode; the last entry is the one that gets selected. Kana typing and the
// Katakana / half-width / full-width modes stay off to keep the menu short.
let japaneseIDs = [
    "com.apple.inputmethod.Kotoeri.RomajiTyping",
    "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
]

func sourceID(_ s: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

func flag(_ s: TISInputSource, _ key: CFString) -> Bool {
    guard let p = TISGetInputSourceProperty(s, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
}

func isEnabled(_ s: TISInputSource) -> Bool { flag(s, kTISPropertyInputSourceIsEnabled) }

func allSources() -> [TISInputSource] {
    guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() else { return [] }
    return list as NSArray as? [TISInputSource] ?? []
}

func currentID() -> String {
    guard let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "" }
    return sourceID(cur)
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

// TISSelectInputSource is asynchronous; poll briefly so the switch has landed
// before we disable anything or exit.
func select(_ s: TISInputSource) {
    let id = sourceID(s)
    let status = TISSelectInputSource(s)
    if status != noErr { fail("select \(id) failed: \(status)") }
    for _ in 0..<50 {
        if currentID() == id { return }
        usleep(20_000)
    }
    fail("select \(id) did not take effect (current: \(currentID()))")
}

let sources = allSources()
let byID = Dictionary(sources.map { (sourceID($0), $0) }, uniquingKeysWith: { a, _ in a })
let kotoeri = sources.filter { sourceID($0).hasPrefix(kotoeriPrefix) }

guard let english = byID[englishID] else { fail("input source not found: \(englishID)") }

// "Japanese is on" means its selectable mode is enabled; the parent alone is
// not enough to show up in the menu.
let japaneseOn = japaneseIDs.allSatisfy { byID[$0].map(isEnabled) ?? false }

if japaneseOn {
    if !isEnabled(english) { TISEnableInputSource(english) }
    select(english)
    for s in kotoeri where isEnabled(s) {
        let status = TISDisableInputSource(s)
        if status != noErr { fail("disable \(sourceID(s)) failed: \(status)") }
    }
    print("japanese: off (\(currentID()))")
} else {
    for id in japaneseIDs {
        guard let s = byID[id] else { fail("input source not found: \(id)") }
        if !isEnabled(s) {
            let status = TISEnableInputSource(s)
            if status != noErr { fail("enable \(id) failed: \(status)") }
        }
    }
    // Re-query: the source object from before enabling may not be selectable.
    guard let target = allSources().first(where: { sourceID($0) == japaneseIDs.last! }) else {
        fail("input source not found after enable: \(japaneseIDs.last!)")
    }
    select(target)
    print("japanese: on (\(currentID()))")
}
