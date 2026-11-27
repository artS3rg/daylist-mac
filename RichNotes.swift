import AppKit
import SwiftUI

extension Entry {
    var formattedNotes: NSAttributedString {
        if let notesRTF, let text = NSAttributedString(rtf: notesRTF, documentAttributes: nil),
           text.string == notes { return text }
        return NSAttributedString(string: notes, attributes: [.font: NSFont.systemFont(ofSize: 14)])
    }

    mutating func setNotes(_ value: NSAttributedString) throws {
        let data = try value.data(from: NSRange(location: 0, length: value.length),
                                  documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        notes = value.string
        notesRTF = notes.isEmpty ? nil : data
    }
}

private func marker(in line: String) -> NSRange? {
    let range = (line as NSString).range(of: #"^(?:• |[0-9]+\. )"#, options: .regularExpression)
    return range.location == NSNotFound ? nil : range
}

final class NotesTextView: NSTextView {
    weak var owner: NoteDocument?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let owner, event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": owner.trait(.boldFontMask); return true
            case "i": owner.trait(.italicFontMask); return true
            case "u": owner.line(.underlineStyle); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        let text = string as NSString
        let paragraph = text.paragraphRange(for: selection)
        let beforeCursor = text.substring(with: NSRange(location: paragraph.location, length: selection.location - paragraph.location))
        guard selection.length == 0, let prefix = marker(in: beforeCursor) else {
            super.insertNewline(sender)
            return
        }
        if (beforeCursor as NSString).length == prefix.length && NSMaxRange(paragraph) <= selection.location + 1 {
            insertText("", replacementRange: NSRange(location: paragraph.location, length: prefix.length))
            return
        }
        let number = Int(beforeCursor.prefix(while: { $0.isNumber }))
        let next = number.flatMap { $0 < Int.max ? "\($0 + 1). " : nil } ?? "• "
        insertText("\n" + next, replacementRange: selection)
    }
}

@MainActor
final class NoteDocument: ObservableObject {
    let view = NotesTextView(frame: .zero)
    init(_ entry: Entry) {
        view.isRichText = true
        view.owner = self
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.usesAdaptiveColorMappingForDarkAppearance = true
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textStorage?.setAttributedString(entry.formattedNotes)
        if view.string.isEmpty { view.typingAttributes = [.font: NSFont.systemFont(ofSize: 14)] }
    }

    private func focus() { view.window?.makeFirstResponder(view) }

    // Use NSTextView's editing path so replacements participate in native undo.
    private func replace(_ range: NSRange, with content: NSAttributedString, select: Bool = true) {
        focus()
        view.insertText(content, replacementRange: range)
        if select { view.setSelectedRange(NSRange(location: range.location, length: content.length)) }
    }

    private var current: [NSAttributedString.Key: Any] {
        let range = view.selectedRange()
        if range.length > 0 { return view.attributedString().attributes(at: range.location, effectiveRange: nil) }
        return view.typingAttributes
    }

    private func transform(_ change: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]) {
        focus()
        let range = view.selectedRange()
        guard range.length > 0 else { view.typingAttributes = change(view.typingAttributes); return }
        let source = view.attributedString().attributedSubstring(from: range)
        let result = NSMutableAttributedString(attributedString: source)
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attrs, run, _ in
            result.setAttributes(change(attrs), range: run)
        }
        replace(range, with: result)
    }

    private func font(_ attrs: [NSAttributedString.Key: Any]) -> NSFont {
        attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
    }

    func trait(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let remove = manager.traits(of: font(current)).contains(trait)
        transform { attrs in
            var next = attrs
            next[.font] = remove ? manager.convert(self.font(attrs), toNotHaveTrait: trait)
                                 : manager.convert(self.font(attrs), toHaveTrait: trait)
            return next
        }
    }

    func size(_ size: CGFloat) {
        transform { attrs in
            var next = attrs
            next[.font] = NSFontManager.shared.convert(self.font(attrs), toSize: size)
            return next
        }
    }

    func attribute(_ key: NSAttributedString.Key, value: Any?) {
        transform { attrs in var next = attrs; next[key] = value; return next }
    }

    func line(_ key: NSAttributedString.Key) {
        attribute(key, value: (current[key] as? NSNumber)?.intValue == 1 ? nil : NSUnderlineStyle.single.rawValue)
    }

    func clear() { transform { _ in [.font: NSFont.systemFont(ofSize: 14)] } }

    func list(numbered: Bool) {
        let text = view.string as NSString
        let range = text.paragraphRange(for: view.selectedRange())
        let result = NSMutableAttributedString(attributedString: view.attributedString().attributedSubstring(from: range))
        let original = result.string as NSString
        var starts = [0]
        var cursor = 0
        while cursor < original.length {
            cursor = NSMaxRange(original.paragraphRange(for: NSRange(location: cursor, length: 0)))
            if cursor < original.length { starts.append(cursor) }
        }
        let remove = starts.allSatisfy { start in
            let line = original.substring(from: start)
            return numbered ? (marker(in: line) != nil && !line.hasPrefix("• ")) : line.hasPrefix("• ")
        }
        for (index, start) in starts.enumerated().reversed() {
            let old = marker(in: original.substring(from: start))?.length ?? 0
            let prefix = remove ? "" : (numbered ? "\(index + 1). " : "• ")
            let attrs = start < result.length ? result.attributes(at: start, effectiveRange: nil) : view.typingAttributes
            result.replaceCharacters(in: NSRange(location: start, length: old), with: NSAttributedString(string: prefix, attributes: attrs))
        }
        replace(range, with: result, select: view.selectedRange().length > 0)
    }

    func link(_ url: URL) {
        if view.selectedRange().length > 0 { attribute(.link, value: url); return }
        var attributes = view.typingAttributes
        attributes[.link] = url
        replace(view.selectedRange(), with: NSAttributedString(string: url.absoluteString, attributes: attributes), select: false)
        view.typingAttributes.removeValue(forKey: .link)
    }
}

struct NotesCanvas: NSViewRepresentable {
    let document: NoteDocument
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document.view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {}
}

struct NotesToolbar: View {
    let document: NoteDocument
    @State private var addingLink = false
    @State private var address = ""
    private var url: URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    private func tool(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 22, height: 22) }
            .help(title).accessibilityLabel(title)
    }
    var body: some View {
        HStack(spacing: 3) {
            tool("bold", "Полужирный") { document.trait(.boldFontMask) }
            tool("italic", "Курсив") { document.trait(.italicFontMask) }
            tool("underline", "Подчёркивание") { document.line(.underlineStyle) }
            tool("strikethrough", "Зачёркивание") { document.line(.strikethroughStyle) }
            Divider()
            Menu {
                ForEach([11, 14, 16, 20, 24, 32], id: \.self) { size in
                    Button("\(size) пт") { document.size(CGFloat(size)) }
                }
            } label: { Image(systemName: "textformat.size") }.help("Размер текста")
            Menu {
                Button("Основной") { document.attribute(.foregroundColor, value: nil) }
                Button("Красный") { document.attribute(.foregroundColor, value: NSColor.systemRed) }
                Button("Синий") { document.attribute(.foregroundColor, value: NSColor.systemBlue) }
                Button("Зелёный") { document.attribute(.foregroundColor, value: NSColor.systemGreen) }
                Button("Фиолетовый") { document.attribute(.foregroundColor, value: NSColor.systemPurple) }
            } label: { Image(systemName: "paintpalette") }.help("Цвет текста")
            Menu {
                Button("Жёлтый") { document.attribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.45)) }
                Button("Розовый") { document.attribute(.backgroundColor, value: NSColor.systemPink.withAlphaComponent(0.35)) }
                Button("Убрать выделение") { document.attribute(.backgroundColor, value: nil) }
            } label: { Image(systemName: "highlighter") }.help("Цвет маркера")
            Divider()
            tool("list.bullet", "Маркированный список") { document.list(numbered: false) }
            tool("list.number", "Нумерованный список") { document.list(numbered: true) }
            Menu {
                Button("По левому краю") { document.view.alignLeft(nil) }
                Button("По центру") { document.view.alignCenter(nil) }
                Button("По правому краю") { document.view.alignRight(nil) }
            } label: { Image(systemName: "text.alignleft") }.help("Выравнивание")
            tool("link", "Добавить ссылку") { address = ""; addingLink = true }
                .popover(isPresented: $addingLink) {
                    VStack(alignment: .leading) {
                        TextField("https://…", text: $address)
                        Button("Вставить ссылку") {
                            if let url { addingLink = false; document.link(url) }
                        }.disabled(url == nil).keyboardShortcut(.defaultAction)
                    }.padding().frame(width: 260)
                }
            tool("eraser", "Очистить форматирование") { document.clear() }
            Spacer(minLength: 0)
        }.buttonStyle(.borderless).fixedSize(horizontal: false, vertical: true)
    }
}
