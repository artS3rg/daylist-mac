import AppKit

@MainActor
func checkNotes() throws {
    _ = NSApplication.shared
    let json = #"{"id":"43369468-C134-4795-AD55-A79CC7BBEE21","title":"Задача","notes":"Один\nДва 🐷","done":false}"#
    var entry = try JSONDecoder().decode(Entry.self, from: Data(json.utf8))
    let doc = NoteDocument(entry)
    precondition(doc.view.string == "Один\nДва 🐷")
    doc.view.setSelectedRange(NSRange(location: 0, length: 4))
    doc.trait(.boldFontMask)
    doc.trait(.italicFontMask)
    doc.line(.underlineStyle)
    doc.view.setSelectedRange(NSRange(location: 0, length: (doc.view.string as NSString).length))
    doc.list(numbered: true)
    precondition(doc.view.string == "1. Один\n2. Два 🐷")
    try entry.setNotes(doc.view.attributedString())
    let copy = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(entry))
    let text = copy.formattedNotes
    precondition(text.string == entry.notes)
    let attrs = text.attributes(at: 4, effectiveRange: nil)
    let traits = NSFontManager.shared.traits(of: attrs[.font] as! NSFont)
    precondition(traits.contains(.boldFontMask) && traits.contains(.italicFontMask))
    precondition((attrs[.underlineStyle] as? NSNumber)?.intValue == 1)
}
