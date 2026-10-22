// winid <owner> [title]: id of that app's largest on-screen window, or the one with that title.
import CoreGraphics
import Foundation
let args = CommandLine.arguments
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0[kCGWindowOwnerName as String] as? String) == args[1] && ($0[kCGWindowLayer as String] as? Int) == 0 }
let h = { (w: [String: Any]) -> Double in ((w[kCGWindowBounds as String] as? NSDictionary)?["Height"] as? NSNumber)?.doubleValue ?? 0 }
let pick = args.count > 2 ? mine.first { ($0[kCGWindowName as String] as? String) == args[2] } : mine.max { h($0) < h($1) }
if let id = pick?[kCGWindowNumber as String] { print(id) } else { exit(1) }
