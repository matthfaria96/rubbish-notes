import AppKit
import SwiftUI

/// The note's images in the footer: a small fanned pile with a count, narrow
/// enough to leave the centred word count alone. A click opens the lightbox.
struct AttachmentShelf: View {
    static let pileLimit = 3
    let urls: [URL]
    let onOpen: (URL) -> Void

    var body: some View {
        let pile = Array(urls.prefix(Self.pileLimit))
        Button { if let first = urls.first { onOpen(first) } } label: {
            ZStack(alignment: .leading) {
                ForEach(Array(pile.enumerated().reversed()), id: \.element) { offset, url in
                    AttachmentThumb(url: url, side: 40)
                        .shadow(color: .black.opacity(0.18), radius: 2, x: 1)
                        .offset(x: CGFloat(offset) * 9)
                        .rotationEffect(.degrees(Double(offset) * 4), anchor: .bottom)
                }
            }
            .frame(width: 40 + CGFloat(pile.count - 1) * 9, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if urls.count > 1 {
                    Text("\(urls.count)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: 7, y: -7)
                }
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .compatGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .help(urls.count == 1 ? L("Open Image") : L("%ld images", urls.count))
    }
}

struct AttachmentThumb: View {
    let url: URL
    let side: CGFloat
    var onOpen: (() -> Void)?
    @StateObject private var image = ViewState<NSImage?>(nil)

    var body: some View {
        Group {
            if let onOpen {
                Button(action: onOpen) { square }
                    .buttonStyle(.plain)
                    .help(L("Open Image"))
            } else {
                square
            }
        }
        .onAppear {
            let state = image
            ThumbnailCache.shared.thumbnail(for: url, size: side) { state.value = $0 }
        }
    }

    private var square: some View {
        Group {
            if let picture = image.value {
                Image(nsImage: picture).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// One image large over the note, its siblings in a strip below. Arrows (or ← →)
/// move through them, Esc or a click outside closes. Never hands off to Quick Look.
struct ImageLightbox: View {
    let urls: [URL]
    @Binding var current: URL?
    let title: String
    let onDelete: (URL) -> Void
    let onDeleteAll: () -> Void
    /// The lightbox wears the note's theme: its page color and text color.
    var theme: EditorTheme = .standard
    @StateObject private var image = ViewState<NSImage?>(nil)
    @FocusState private var focused: Bool

    private var chrome: Color { Color(nsColor: theme.backgroundNS()) }
    private var ink: Color { Color(nsColor: theme.textNS()) }

    private var index: Int { current.flatMap { urls.firstIndex(of: $0) } ?? 0 }

    var body: some View {
        ZStack {
            chrome.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            picture
            if urls.count > 1 {
                HStack {
                    arrow("chevron.left", by: -1)
                    Spacer()
                    arrow("chevron.right", by: 1)
                }
                .padding(.horizontal, 16)
            }
            VStack(spacing: 0) {
                ZStack(alignment: .trailing) {
                    toolbar.frame(maxWidth: .infinity)
                    moreMenu.padding(.trailing, 16)
                }
                .padding(.top, 16)
                Spacer()
                if urls.count > 1 { filmstrip }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onExitCommand(perform: close)
        .task(id: current) { await load() }
    }

    @ViewBuilder
    private var picture: some View {
        if let picture = image.value {
            // Never blown up past its own size, so small images stay sharp.
            Image(nsImage: picture)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: picture.size.width, maxHeight: picture.size.height)
                .padding(.horizontal, 70)
                .padding(.top, 64)
                .padding(.bottom, urls.count > 1 ? 96 : 64)
                .shadow(color: .black.opacity(0.5), radius: 20)
                .id(current)
                .transition(.opacity)
        } else {
            ProgressView().controlSize(.large)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            if let url = current {
                tool("doc.on.doc", "Copy Image") { NoteStore.copyImage(url) }
                tool("square.and.arrow.down", "Save Image…") { NoteStore.exportImage(url, named: title) }
                tool("trash", "Delete Image…") { onDelete(url) }
            }
            Divider().frame(height: 18).overlay(ink.opacity(0.3))
            tool("xmark", "Close", action: close)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(chrome.opacity(0.9), in: Capsule())
        .overlay(Capsule().strokeBorder(ink.opacity(0.15)))
    }

    /// Whole-set actions, tucked in the corner; both ask before doing anything.
    private var moreMenu: some View {
        Menu {
            Button("Save All Images…", systemImage: "square.and.arrow.down.on.square") {
                NoteStore.exportImages(urls, named: title)
            }
            Button("Delete All Images…", systemImage: "trash", role: .destructive, action: onDeleteAll)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(chrome.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(ink.opacity(0.15)))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .labelStyle(.titleAndIcon)
        .help("More")
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(urls, id: \.self) { url in
                        AttachmentThumb(url: url, side: 52) { current = url }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(ink, lineWidth: url == current ? 2 : 0)
                            )
                            .opacity(url == current ? 1 : 0.55)
                            .id(url)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: min(CGFloat(urls.count) * 60 + 24, 560), maxHeight: 68)
            .background(chrome.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.bottom, 14)
            .onChange(of: current, initial: true) {
                withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(current, anchor: .center) }
            }
            .animation(.smooth(duration: 0.2), value: current)
        }
    }

    private func tool(_ symbol: String, _ help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ink.opacity(0.9))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }

    private func arrow(_ symbol: String, by offset: Int) -> some View {
        Button { step(offset) } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ink.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(chrome.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(ink.opacity(0.15)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func close() {
        withAnimation(ImageLightbox.motion) { current = nil }
    }

    /// Opening and closing both use this, so the expansion and its reverse match.
    static let motion = Animation.spring(duration: 0.38, bounce: 0.12)

    private func step(_ offset: Int) {
        guard !urls.isEmpty else { return }
        current = urls[(index + offset + urls.count) % urls.count]
    }

    /// Screen-sized decode off the main thread, so huge photos stay smooth.
    private func load() async {
        guard let url = current else { return }
        let side = (NSScreen.main?.frame.size).map { max($0.width, $0.height) * 2 } ?? 3000
        let state = image
        ThumbnailCache.shared.thumbnail(for: url, size: side / 2) { picture in
            guard current == url else { return }
            withAnimation(.easeOut(duration: 0.15)) { state.value = picture }
        }
    }
}

/// The images corner before there are any: shows where they will live.
struct ImagesHintButton: View {
    @Binding var open: Bool

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.callout)
                .foregroundStyle(open ? .primary : .secondary)
                .modifier(LegacyFooterPadding())
        }
        .compatFooterButton()
        .help("Images: paste or drop them here")
    }
}

/// How to add images, opened from the empty images corner.
struct ImagesHintPanel: View {
    let onChoose: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Images", systemImage: "photo.on.rectangle.angled").font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close")
            }
            Text("Paste an image (⌘V) or drop one on the note. It stays here in this corner, never inside your text.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose Images…", systemImage: "plus") {
                onClose()
                onChoose()
            }
            .compatGlassProminentButtonStyle()
        }
        .padding(14)
        .frame(width: 280)
    }
}
