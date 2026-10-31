import AppKit
import UniformTypeIdentifiers

/// A text file from outside the notes, open in a window of its own (Open
/// Files › Open in Separate Window): no
/// sidebar, tabs, blocks or images, just the text, saved back to the same
/// file. It is never added to the notes. NSDocument does the saving (in place,
/// coordinated, within the access the sandbox grants to files the person
/// opened), so no extra entitlement is needed.
@objc(RNPlainTextDocument)
final class PlainTextDocument: NSDocument {
    /// The text as last read from disk; the window's text view holds the live copy.
    private(set) var text = ""
    /// Written back in the encoding it was read in.
    private(set) var encoding: String.Encoding = .utf8
    weak var textView: NSTextView?

    override class var autosavesInPlace: Bool { true }
    override class var readableTypes: [String] { [UTType.plainText.identifier] }
    override class var writableTypes: [String] { [UTType.plainText.identifier] }
    override class func isNativeType(_ type: String) -> Bool { true }

    /// Opens the file in its window, or brings that window forward if it is open.
    static func open(_ url: URL) {
        let controller = NSDocumentController.shared
        if let open = controller.document(for: url) {
            open.showWindows()
            return
        }
        do {
            let document = try PlainTextDocument(contentsOf: url, ofType: UTType.plainText.identifier)
            controller.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            NSApp.activate()
        } catch {
            NSApp.presentError(error)
        }
    }

    override func makeWindowControllers() {
        addWindowController(PlainTextWindowController(document: self))
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard data.count <= NoteStore.maxFileBytes else { throw CocoaError(.fileReadTooLarge) }
        let decoded = Self.decode(data)
        text = decoded.text
        encoding = decoded.encoding
        // Reverting, or the file changed in another app.
        if let textView, textView.string != text { textView.string = text }
    }

    override func data(ofType typeName: String) throws -> Data {
        let current = textView?.string ?? text
        guard let data = current.data(using: encoding) ?? current.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        if current.data(using: encoding) == nil { encoding = .utf8 }
        text = current
        return data
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.string = textView?.string ?? text
        view.font = textView?.font ?? .systemFont(ofSize: 12)
        view.sizeToFit()
        return NSPrintOperation(view: view, printInfo: info)
    }

    /// UTF-8 (with or without a byte-order mark), UTF-16 with a mark, else
    /// Windows Latin 1, which reads any bytes.
    static func decode(_ data: Data) -> (text: String, encoding: String.Encoding) {
        if let text = String(data: data, encoding: .utf8) {
            return (text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text, .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return (text, .utf16)
        }
        if let text = String(data: data, encoding: .windowsCP1252) { return (text, .windowsCP1252) }
        return (String(decoding: data, as: UTF8.self), .utf8)
    }
}

/// The plain window: one text view in the editor's font and theme colours.
/// Typing is saved a second after it stops, like the notes.
final class PlainTextWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let textView: NSTextView
    private var pendingSave: DispatchWorkItem?
    private var prefsObserver: NSObjectProtocol?
    /// Where the last plain window opened, so the next one cascades from it.
    private static var lastTopLeft: NSPoint?

    init(document: PlainTextDocument) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 320, height: 220)
        window.subtitle = L("Plain text")
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        textView = scroll.documentView as! NSTextView
        window.contentView = scroll
        super.init(window: window)
        window.delegate = self
        configureTextView(text: document.text)
        document.textView = textView
        applyLook()
        placeWindow(window)
        prefsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyLook()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let prefsObserver { NotificationCenter.default.removeObserver(prefsObserver) }
    }

    private func configureTextView(text: String) {
        PlainTextLook.configure(textView)
        textView.textContainerInset = NSSize(width: 28, height: 22)
        textView.string = text
        textView.delegate = self
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    /// The editor's font, spelling choice and theme, kept current with Settings.
    private func applyLook() {
        let theme = PlainTextLook.apply(to: textView)
        textView.enclosingScrollView?.backgroundColor = theme.backgroundNS()
        guard let window else { return }
        window.backgroundColor = theme.backgroundNS()
        window.titlebarAppearsTransparent = theme.background != nil
        let choice = AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: Prefs.appearance) ?? "") ?? .system
        let dark = choice.scheme.map { $0 == .dark } ?? theme.isDark
        window.appearance = dark.map { NSAppearance(named: $0 ? .darkAqua : .aqua) } ?? nil
    }

    private func placeWindow(_ window: NSWindow) {
        if let last = Self.lastTopLeft {
            Self.lastTopLeft = window.cascadeTopLeft(from: last)
        } else {
            window.center()
            Self.lastTopLeft = window.cascadeTopLeft(from: .zero)
        }
    }

    func textDidChange(_ notification: Notification) {
        // Typing also counts through the undo manager; this covers every other
        // kind of change (dictation, services, accessibility), so none is left unsaved.
        if plainDocument?.isDocumentEdited == false { plainDocument?.updateChangeCount(.changeDone) }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.plainDocument?.autosave(withImplicitCancellability: false) { _ in }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        plainDocument?.undoManager
    }

    private var plainDocument: PlainTextDocument? { document as? PlainTextDocument }

    func windowWillClose(_ notification: Notification) {
        pendingSave?.cancel()
    }
}

/// How plain text is shown, in its own window and for Open Files in the
/// notes window: plain text only, in the editor's font, spacing and theme.
enum PlainTextLook {
    /// No rich text, images or automatic substitutions.
    static func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
    }

    /// Applies the font, line spacing, colours and spelling from Settings; returns the theme.
    @discardableResult
    static func apply(to textView: NSTextView, defaults: UserDefaults = .standard) -> EditorTheme {
        let theme = EditorTheme.named(defaults.string(forKey: Prefs.editorTheme) ?? EditorTheme.standard.id)
        let accent = theme.accentNS(fallback: IconStyle.current.accentNS)
        let size = defaults.object(forKey: Prefs.fontSize) as? Double ?? Prefs.defaultFontSize
        let font = FontChoice.font(defaults.string(forKey: Prefs.fontName) ?? FontChoice.defaultName, size: size)
        if textView.font != font { textView.font = font }
        // The editor's line spacing.
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ceil(font.pointSize * 1.45)
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        if let storage = textView.textStorage {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        }
        textView.textColor = theme.textNS()
        textView.backgroundColor = theme.backgroundNS()
        textView.insertionPointColor = accent
        textView.selectedTextAttributes = [.backgroundColor: theme.selectionNS(fallback: accent)]
        textView.isContinuousSpellCheckingEnabled = defaults.bool(forKey: Prefs.spellCheck)
        return theme
    }
}
