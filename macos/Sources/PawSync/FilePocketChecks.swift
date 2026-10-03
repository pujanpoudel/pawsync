import AppKit

/// Exercises file safety using owned, disposable fixtures, never user files.
@MainActor enum FilePocketChecks {
    static func run() throws {
        let fm=FileManager.default
        let root=fm.temporaryDirectory.appendingPathComponent("PawSync-pocket-check-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        func require(_ condition:Bool,_ message:String) throws { if !condition { throw PawError.message(message) } }
        let a=root.appendingPathComponent("a"),b=root.appendingPathComponent("b"),legacy=root.appendingPathComponent("previous-pocket")
        for directory in [a,b,legacy] { try fm.createDirectory(at:directory,withIntermediateDirectories:true) }
        let name=" notes — café.txt"
        let first=a.appendingPathComponent(name),second=b.appendingPathComponent(name)
        let data=Data("Original file contents".utf8)
        try data.write(to:first);try Data("Different original contents".utf8).write(to:second)
        let previous=legacy.appendingPathComponent(UUID().uuidString+"__earlier.txt")
        try data.write(to:previous)
        let inbox=PetFileInbox(legacyDirectory:legacy)
        try require(inbox.files.isEmpty && inbox.hasEarlierCopies,"Old copies were reloaded into a temporary pocket.")
        try require(try inbox.catchFiles([first,second]) == 2,"Distinct originals with the same name were not accepted.")
        try require(inbox.files.allSatisfy{$0.name == name} && Set(inbox.files.map(\.url)) == Set([first,second]),"Pocket renamed a file or changed its URL.")
        try require(try fm.contentsOfDirectory(atPath:legacy.path).count == 1,"Catching created a persistent copy.")
        try require(!inbox.canAcceptDrop([first]) && (try inbox.catchFiles([first])) == 0,"Self-drop/duplicate handling is incorrect.")
        let caught=inbox.files.first{$0.url == first}!
        inbox.finishDrag(caught,operation:[])
        try require(inbox.files.count == 2,"Canceling a drag released the file.")
        inbox.finishDrag(caught,operation:.copy)
        try require(inbox.files.count == 1 && (try Data(contentsOf:first)) == data,"Successful drag-out damaged an original or did not release it.")
        inbox.empty()
        try require(inbox.files.isEmpty && fm.fileExists(atPath:second.path) && (try Data(contentsOf:previous)) == data,"Emptying the pocket deleted an original or earlier copy.")
        try require(PetFileInbox(legacyDirectory:legacy).files.isEmpty,"Files persisted after restarting the pocket.")
        // There is no size-based copy/storage budget: references to large files
        // take the same memory as references to small files.
        let large=root.appendingPathComponent("large-file.bin")
        _=fm.createFile(atPath:large.path,contents:nil)
        let handle=try FileHandle(forWritingTo:large);try handle.truncate(atOffset:101*1024*1024);try handle.close()
        try require(inbox.canAccept([large]),"A reference-only pocket rejects a large file unnecessarily.")
        _=try inbox.catchFiles([large]);try fm.removeItem(at:large);inbox.reload()
        try require(inbox.files.isEmpty,"A missing original left a stuck pocket entry.")
        print("File pocket checks passed: exact original names/URLs; no persistent copies; same-name files; duplicates/self-drop; canceled/successful drag-out; originals survive release/clear; earlier copies preserved; session-only lifecycle; large and missing originals.")
    }
}
