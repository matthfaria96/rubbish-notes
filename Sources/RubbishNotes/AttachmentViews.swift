import AppKit
import SwiftUI

/// The note's images in the footer: a peek of a few thumbnails that expands
/// into a gallery of all of them, and collapses back.
struct AttachmentShelf: View {
    static let peekLimit = 4
    let urls: [URL]
    @Binding var expanded: Bool
    let onOpen: (URL) -> Void
    let onExportAll: () -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        Group {
            if expanded { gallery } else { peek }
        }
        .compatGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.smooth(duration: 0.28), value: expanded)
    }

    private var peek: some View {
        HStack(spacing: 6) {
            ForEach(urls.prefix(Self.peekLimit), id: \.self) { url in
                AttachmentThumb(url: url, side: 40) { onOpen(url) }
            }
            if urls.count > Self.peekLimit {
                Button { expanded = true } label: {
                    Text("+\(urls.count - Self.peekLimit)")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 40, height: 40)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show All Images")
            }
            toggle
        }
        .padding(5)
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(urls.count == 1 ? L("1 image") : L("%ld images", urls.count))
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 12)
                Button(action: onExportAll) { Image(systemName: "square.and.arrow.up.on.square") }
                    .buttonStyle(.plain)
                    .help("Export All Images…")
                Button(action: onDeleteAll) { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .help("Delete All Images…")
                toggle
            }
            .foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: 8)], spacing: 8) {
                    ForEach(urls, id: \.self) { url in
                        AttachmentThumb(url: url, side: 64) { onOpen(url) }
                    }
                }
            }
            .frame(height: min(220, CGFloat((urls.count + 3) / 4) * 72 - 8))
        }
        .padding(10)
        .frame(width: 320)
    }

    /// Opens the gallery (pushing the rest of the footer away) or folds it back.
    private var toggle: some View {
        Button { expanded.toggle() } label: {
            Image(systemName: expanded ? "chevron.down" : "chevron.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L(expanded ? "Collapse" : "Show All Images"))
    }
}

struct AttachmentThumb: View {
    let url: URL
    let side: CGFloat
    let onOpen: () -> Void
    @StateObject private var image = ViewState<NSImage?>(nil)

    var body: some View {
        Button(action: onOpen) {
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
        .buttonStyle(.plain)
        .help(L("Open Image"))
        .onAppear {
            let state = image
            ThumbnailCache.shared.thumbnail(for: url, size: side) { state.value = $0 }
        }
    }
}

/// One image large over the note: arrows (or ← →) move through them, Esc closes.
struct ImageLightbox: View {
    let urls: [URL]
    @Binding var current: URL?
    let title: String
    let onDelete: (URL) -> Void
    let onDeleteAll: () -> Void
    @StateObject private var image = ViewState<NSImage?>(nil)
    @FocusState private var focused: Bool

    private var index: Int { current.flatMap { urls.firstIndex(of: $0) } ?? 0 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture { current = nil }
            if let picture = image.value {
                // Never blown up past its own size, so small images stay sharp.
                Image(nsImage: picture)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: picture.size.width, maxHeight: picture.size.height)
                    .padding(.horizontal, 70)
                    .padding(.vertical, 64)
                    .shadow(color: .black.opacity(0.5), radius: 20)
            } else {
                ProgressView().controlSize(.large)
            }
            if urls.count > 1 {
                HStack {
                    arrow("chevron.left", by: -1)
                    Spacer()
                    arrow("chevron.right", by: 1)
                }
                .padding(.horizontal, 16)
            }
            VStack {
                toolbar
                Spacer()
                if urls.count > 1 {
                    Text("\(index + 1) / \(urls.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 18)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onExitCommand { current = nil }
        .task(id: current) { await load() }
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            if let url = current {
                tool("doc.on.doc", "Copy Image") { NoteStore.copyImage(url) }
                tool("square.and.arrow.up", "Export Image…") { NoteStore.exportImage(url, named: title) }
                if urls.count > 1 {
                    tool("square.and.arrow.up.on.square", "Export All Images…") { NoteStore.exportImages(urls, named: title) }
                }
                tool("trash", "Delete Image…") { onDelete(url) }
                if urls.count > 1 {
                    tool("trash.square", "Delete All Images…", action: onDeleteAll)
                }
            }
            Divider().frame(height: 18).overlay(Color.white.opacity(0.3))
            tool("xmark", "Close") { current = nil }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(.top, 16)
    }

    private func tool(_ symbol: String, _ help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
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
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.4), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func step(_ offset: Int) {
        guard !urls.isEmpty else { return }
        current = urls[(index + offset + urls.count) % urls.count]
    }

    /// Screen-sized decode off the main thread, so huge photos stay smooth.
    private func load() async {
        image.value = nil
        guard let url = current else { return }
        let side = (NSScreen.main?.frame.size).map { max($0.width, $0.height) * 2 } ?? 3000
        let state = image
        ThumbnailCache.shared.thumbnail(for: url, size: side / 2) { picture in
            if current == url { state.value = picture }
        }
    }
}
