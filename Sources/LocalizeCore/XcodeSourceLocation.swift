import Foundation

/// Builds the open-document event used by Xcode 26's xed tool, without spawning a subprocess.
public enum XcodeSourceLocation {
    public static func event(file: URL, line: Int) throws -> NSAppleEventDescriptor {
        guard file.isFileURL else { throw StudioError.message("Xcode navigation requires a local source file.") }
        let bookmark = try file.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let documents = NSAppleEventDescriptor.list()
        guard let document = NSAppleEventDescriptor(descriptorType: 0x626D726B, data: bookmark) else { throw StudioError.message("Could not prepare the source file bookmark.") }
        documents.insert(document, at: 1) // bmrk
        let properties = NSAppleEventDescriptor.record()
        properties.setDescriptor(NSAppleEventDescriptor(int32: Int32(clamping: max(1, line))), forKeyword: 0x6C696E65) // line
        let event = NSAppleEventDescriptor(eventClass: 0x61657674, eventID: 0x6F646F63, targetDescriptor: nil, returnID: -1, transactionID: 0) // aevt / odoc
        event.setParam(documents, forKeyword: 0x2D2D2D2D) // direct object
        event.setParam(properties, forKeyword: 0x70726474) // prdt
        return event
    }
}
