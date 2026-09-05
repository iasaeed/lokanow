import Foundation

public enum FileDiff {
    /// A valid single-hunk comparison with common outer context trimmed.
    /// Linear memory/time even for large generated resources.
    public static func unified(_ change: FileChange) -> String {
        let old = change.before.map { String(decoding: $0, as: UTF8.self).components(separatedBy: "\n") } ?? []
        let new = String(decoding: change.after, as: UTF8.self).components(separatedBy: "\n")
        var prefix = 0
        while prefix < min(old.count, new.count) && old[prefix] == new[prefix] { prefix += 1 }
        if prefix == old.count && prefix == new.count { return "No textual changes." }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix && old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        let start = max(0, prefix - 3), endOld = min(old.count, old.count - suffix + 3), endNew = min(new.count, new.count - suffix + 3)
        var lines = ["--- \(change.before == nil ? "/dev/null" : change.url.lastPathComponent)", "+++ \(change.url.lastPathComponent)", "@@ -\(start + 1),\(endOld - start) +\(start + 1),\(endNew - start) @@"]
        lines += old[start..<prefix].map { " " + $0 }
        lines += old[prefix..<(old.count - suffix)].map { "-" + $0 }
        lines += new[prefix..<(new.count - suffix)].map { "+" + $0 }
        lines += old[(old.count - suffix)..<endOld].map { " " + $0 }
        return lines.joined(separator: "\n")
    }
}
