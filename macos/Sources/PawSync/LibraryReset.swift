import AppKit

@MainActor enum LibraryReset {
    static func archiveLocalState(root:URL=PetStore.root) throws {
        let folder=root.appendingPathComponent("Backups/reset-everything-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        // Photos, imported sprite art, purchase cache and Keychain credentials
        // are never part of an earned-progress/preferences reset.
        for name in ["Library/progress.json","Wardrobe","activity.json","Presentation","Tools","Reminders","Features"] {
            let source=root.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath:source.path) else{continue}
            let destination=folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            try FileManager.default.moveItem(at:source,to:destination)
        }
        let bundleID=Bundle.main.bundleIdentifier ?? "com.pawsync.desktop"
        if let domain=UserDefaults.standard.persistentDomain(forName:bundleID) {
            let data=try PropertyListSerialization.data(fromPropertyList:domain,format:.binary,options:0)
            try data.write(to:folder.appendingPathComponent("preferences.plist"),options:.atomic)
        }
        UserDefaults.standard.removePersistentDomain(forName:bundleID)
    }
}
