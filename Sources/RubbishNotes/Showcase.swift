import Foundation

/// Screenshot hook for the witchmymac showcase page. `RUBBISHNOTES_SHOWCASE`
/// is a comma-separated list read once at launch:
/// `blocks` opens the footer blocks panel, `lightbox` opens the open note's
/// first image, `settings=general|editor|themes|about` opens Settings on that
/// tab. Without the variable nothing changes.
enum Showcase {
    static let options: [String: String] = {
        guard let raw = ProcessInfo.processInfo.environment["RUBBISHNOTES_SHOWCASE"] else { return [:] }
        return raw.split(separator: ",").reduce(into: [String: String]()) { result, item in
            let parts = item.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let key = parts.first, !key.isEmpty else { return }
            result[key] = parts.count > 1 ? parts[1] : ""
        }
    }()

    static func has(_ key: String) -> Bool { options[key] != nil }
    static func value(_ key: String) -> String? { options[key] }
}
