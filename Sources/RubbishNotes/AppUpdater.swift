import AppKit
import Combine
import Sparkle
import SwiftUI

/// In-app updates through Sparkle, as in Sirena and Wineup. The feed (SUFeedURL), the EdDSA public
/// key (SUPublicEDKey) and the daily check live in Support/Info.plist; versions are signed with the
/// witchmymac EdDSA key and the app with the witchmymac certificate. The app is sandboxed, so
/// Sparkle installs through its Installer and Downloader XPC services (SUEnableInstallerLauncherService,
/// SUEnableDownloaderService, and the mach-lookup exceptions in RubbishNotes.entitlements).
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    /// False while a check or an install is already under way.
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    private init() {}

    /// Starts Sparkle's scheduler (daily check). Call once at launch.
    /// Test copies (another bundle id) don't check, unless RUBBISHNOTES_UPDATES=1.
    func start() {
        guard controller == nil else { return }
        let env = ProcessInfo.processInfo.environment
        guard Bundle.main.bundleIdentifier == "local.rubbishnotes.app" || env["RUBBISHNOTES_UPDATES"] != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            DispatchQueue.main.async { self?.canCheckForUpdates = canCheck }
        }
        controller.startUpdater()
    }

    /// "Check for Updates…": always shows a result, even "You're up to date".
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// App menu item and About button: disabled while a check is already under way.
struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Button("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
