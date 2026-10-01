import AppKit
import Foundation
import ImageIO
import Darwin

struct ImportedPackageMetadata: Codable {
    let id: String
    let displayName: String
    let description: String?
    let spritesheetPath: String?
    let spriteVersionNumber: Int?
    let sourceUrl: String?
    let author: String?
    var pawsyncOrigin:String? = nil
    var pawsyncSource:String? = nil
    func validate() throws {
        guard id.range(of:"^[a-z0-9][a-z0-9._-]{0,79}$",options:.regularExpression) != nil,
              !id.contains(".."), !displayName.isEmpty, displayName.count <= 120,
              (description?.count ?? 0) <= 4000,
              spritesheetPath == nil || spritesheetPath == "spritesheet.webp",
              spriteVersionNumber == nil || spriteVersionNumber == 1 || spriteVersionNumber == 2 else { throw PawError.message("Invalid or unsupported pet metadata.") }
    }
}

enum PetInstallation {
    private struct Journal: Codable { let folder: String; let stage: String; let backup: String; let replacing: Bool }
    static var root: URL { PetStore.root.appendingPathComponent("ImportedPets",isDirectory:true) }
    static func installed(root: URL = root) -> [ImportedPet] {
        let directories=(try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey])) ?? []
        return directories.filter { !$0.lastPathComponent.hasPrefix(".") }.compactMap { directory in
            guard let values=try? directory.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey]), values.isSymbolicLink != true, values.isDirectory == true,
                  let metadata=try? inspectInstalled(directory),
                  directory.lastPathComponent == metadata.id else { return nil }
            return ImportedPet(id:"community-\(metadata.id)",name:metadata.displayName,folder:metadata.id,columns:8,rows:metadata.spriteVersionNumber == 2 ? 11 : 9,source:metadata.pawsyncSource ?? metadata.sourceUrl ?? "Local import",author:metadata.author ?? "Community",local:true,origin:metadata.pawsyncOrigin ?? "local")
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private static func inspectInstalled(_ directory:URL) throws -> ImportedPackageMetadata {
        let entries=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey])
        guard Set(entries.map(\.lastPathComponent)) == ["pet.json","spritesheet.webp"] else { throw PawError.message("Invalid installed pet layout.") }
        for entry in entries {
            let values=try entry.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey])
            let limit=entry.lastPathComponent == "pet.json" ? 65536 : 100*1024*1024
            guard values.isSymbolicLink != true, values.isRegularFile == true, (values.fileSize ?? Int.max) <= limit else { throw PawError.message("Invalid installed pet file.") }
        }
        let manifest=try Data(contentsOf:directory.appendingPathComponent("pet.json"))
        let metadata=try JSONDecoder().decode(ImportedPackageMetadata.self,from:manifest)
        try metadata.validate()
        let imageURL=directory.appendingPathComponent("spritesheet.webp")
        let handle=try FileHandle(forReadingFrom:imageURL)
        let header=try handle.read(upToCount:12) ?? Data()
        try handle.close()
        guard header.count == 12, header.prefix(4) == Data("RIFF".utf8), header.subdata(in:8..<12) == Data("WEBP".utf8),
              let source=CGImageSourceCreateWithURL(imageURL as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              validImage(source,metadata:metadata) else { throw PawError.message("Invalid installed pet image.") }
        return metadata
    }
    private static func validImage(_ source:CGImageSource,metadata:ImportedPackageMetadata)->Bool {
        guard CGImageSourceGetCount(source) == 1,
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,[kCGImageSourceShouldCache:false] as CFDictionary) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? Int, let height=properties[kCGImagePropertyPixelHeight] as? Int,
              width <= 2048,height <= 3072,properties[kCGImagePropertyHasAlpha] as? Bool == true else { return false }
        if metadata.spriteVersionNumber == 2 { return width == 1536 && height == 2288 }
        return width.isMultiple(of:8) && height.isMultiple(of:9) && width/8 >= 192 && height/9 >= 208
    }
    static func validate(_ files: [String:Data]) throws -> (ImportedPackageMetadata, Data, Data) {
        let allowed:Set<String> = ["pet.json","spritesheet.webp","character-sheet.png","pose-sheet.png"]
        guard (2...4).contains(files.count) else { throw PawError.message("A pet package needs pet.json and spritesheet.webp, with optional character and pose sheets.") }
        let paths=Array(files.keys), parents=Set(paths.map { ($0 as NSString).deletingLastPathComponent })
        guard parents.count == 1, parents.first!.split(separator:"/").count <= 1,
              paths.allSatisfy({ !$0.hasPrefix("/") && !$0.contains("\\") && !$0.contains(":") && $0.split(separator:"/",omittingEmptySubsequences:false).allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}) }),
              Set(paths.map { ($0 as NSString).lastPathComponent }).isSubset(of:allowed),
              paths.contains(where:{($0 as NSString).lastPathComponent == "pet.json"}),
              paths.contains(where:{($0 as NSString).lastPathComponent == "spritesheet.webp"}),
              files.allSatisfy({ path,data in ["character-sheet.png","pose-sheet.png"].contains((path as NSString).lastPathComponent) ? data.count <= 15*1024*1024 && data.prefix(8) == Data([137,80,78,71,13,10,26,10]) : true }),
              let manifest=files.first(where:{($0.key as NSString).lastPathComponent == "pet.json"})?.value,manifest.count <= 65536,
              let image=files.first(where:{($0.key as NSString).lastPathComponent == "spritesheet.webp"})?.value,image.count <= 100*1024*1024 else { throw PawError.message("Invalid pet package layout.") }
        let metadata=try JSONDecoder().decode(ImportedPackageMetadata.self,from:manifest); try metadata.validate()
        guard image.count >= 12, image.prefix(4) == Data("RIFF".utf8), image.subdata(in:8..<12) == Data("WEBP".utf8),
              let source=CGImageSourceCreateWithData(image as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              validImage(source,metadata:metadata) else { throw PawError.message("A pet needs a bounded, transparent WebP sprite sheet with the expected frame layout.") }
        return (metadata,manifest,image)
    }
    static func localFiles(_ url: URL) throws -> [String:Data] {
        let values=try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isSymbolicLink != true else { throw PawError.message("Symbolic-link imports are not allowed.") }
        if values.isDirectory != true {
            guard (values.fileSize ?? Int.max) <= 50*1024*1024 else { throw PawError.message("Pet ZIPs may be at most 50 MB.") }
            return try SafeArchive.unpack(Data(contentsOf:url,options:.mappedIfSafe))
        }
        let entries=try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:[.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey])
        let names=Set(entries.map(\.lastPathComponent))
        guard names.isSubset(of:["pet.json","spritesheet.webp","character-sheet.png","pose-sheet.png"]),names.isSuperset(of:["pet.json","spritesheet.webp"]) else { throw PawError.message("Choose a folder containing pet.json, spritesheet.webp, and optional character/pose sheets.") }
        var files:[String:Data]=[:]
        for entry in entries {
            let value=try entry.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey])
            guard value.isSymbolicLink != true,value.isRegularFile == true,(value.fileSize ?? Int.max) <= 100*1024*1024 else { throw PawError.message("Unsafe pet file.") }
            files[entry.lastPathComponent]=try Data(contentsOf:entry,options:.mappedIfSafe)
        }
        return files
    }
    static func install(_ files: [String:Data], expectedID: String? = nil, root: URL = root, origin:String="local", source:String?=nil) throws -> String {
        var (metadata,_,image)=try validate(files)
        guard ["local","catalog","codex"].contains(origin) else { throw PawError.message("Unknown import source.") }
        metadata.pawsyncOrigin=origin; metadata.pawsyncSource=source
        let manifest=try JSONEncoder().encode(metadata)
        guard expectedID == nil || metadata.id == expectedID else { throw PawError.message("The pet package does not match its catalog ID.") }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        guard (try root.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else { throw PawError.message("The pet installation root cannot be a symbolic link.") }
        // Kernel locks are released even after a process crash; no stale PID lock.
        let descriptor=open(root.appendingPathComponent(".install.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard descriptor >= 0 else { throw PawError.message("Could not open the pet installation lock.") }
        defer { close(descriptor) }
        guard flock(descriptor,LOCK_EX|LOCK_NB) == 0 else { throw PawError.message("Another pet installation is active. Retry after it finishes.") }
        defer { flock(descriptor,LOCK_UN) }
        try recover(root:root)
        let nonce=UUID().uuidString,folder=metadata.id
        let stage=".stage-\(nonce)",backup=".backup-\(nonce)",target=root.appendingPathComponent(folder)
        let journal=Journal(folder:folder,stage:stage,backup:backup,replacing:FileManager.default.fileExists(atPath:target.path))
        let staged=root.appendingPathComponent(stage),old=root.appendingPathComponent(backup),journalURL=root.appendingPathComponent(".journal.json")
        try FileManager.default.createDirectory(at:staged,withIntermediateDirectories:false)
        do {
            try manifest.write(to:staged.appendingPathComponent("pet.json"),options:.atomic)
            try image.write(to:staged.appendingPathComponent("spritesheet.webp"),options:.atomic)
            try JSONEncoder().encode(journal).write(to:journalURL,options:.atomic)
            if journal.replacing { try FileManager.default.moveItem(at:target,to:old) }
            try FileManager.default.moveItem(at:staged,to:target)
            try FileManager.default.removeItem(at:journalURL)
            if journal.replacing { try? FileManager.default.removeItem(at:old) }
        } catch { try? recover(root:root); if FileManager.default.fileExists(atPath:staged.path) { try? FileManager.default.removeItem(at:staged) }; throw error }
        return "community-\(metadata.id)"
    }
    static func recover(root: URL = root) throws {
        let journalURL=root.appendingPathComponent(".journal.json")
        guard FileManager.default.fileExists(atPath:journalURL.path) else { return }
        let journal=try JSONDecoder().decode(Journal.self,from:Data(contentsOf:journalURL))
        guard journal.folder.range(of:"^[a-z0-9][a-z0-9._-]{0,79}$",options:.regularExpression) != nil,!journal.folder.contains(".."),
              journal.stage.hasPrefix(".stage-"),UUID(uuidString:String(journal.stage.dropFirst(7))) != nil,
              journal.backup.hasPrefix(".backup-"),UUID(uuidString:String(journal.backup.dropFirst(8))) != nil else { throw PawError.message("Pet install recovery needs review; its journal is invalid.") }
        let target=root.appendingPathComponent(journal.folder),stage=root.appendingPathComponent(journal.stage),backup=root.appendingPathComponent(journal.backup)
        let exists: (String) -> Bool = { FileManager.default.fileExists(atPath:$0) }
        if !exists(target.path),exists(backup.path) { try FileManager.default.moveItem(at:backup,to:target) }
        else if exists(target.path),exists(backup.path) {
            // A complete new target can commit; an invalid target keeps the old backup.
            do { _=try validate(localFiles(target)); try FileManager.default.removeItem(at:backup) }
            catch { throw PawError.message("Pet installation is ambiguous. The previous version is retained for recovery.") }
        } else if !exists(target.path),journal.replacing {
            throw PawError.message("Pet installation is ambiguous. Staged files were retained for recovery.")
        } else if !exists(target.path),exists(stage.path),!journal.replacing {
            _=try validate(localFiles(stage)); try FileManager.default.moveItem(at:stage,to:target)
        }
        if exists(stage.path) { try FileManager.default.removeItem(at:stage) }
        try FileManager.default.removeItem(at:journalURL)
    }
    static func remove(_ pet: ImportedPet) throws {
        guard pet.local == true,installed().contains(where:{$0.id == pet.id}) else { throw PawError.message("Bundled companions cannot be removed.") }
        // Recovery through the system Trash remains available.
        try FileManager.default.trashItem(at:pet.directory,resultingItemURL:nil)
    }
}
