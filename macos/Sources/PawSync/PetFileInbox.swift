import AppKit
import Combine
import SwiftUI

struct PetInboxFile:Identifiable,Codable,Equatable {
    var id:String
    var name:String
    var size:Int64
    var added:Date
    var idValue:UUID { UUID(uuidString:id) ?? UUID() }
    var url:URL { PetStore.root.appendingPathComponent("PetInbox",isDirectory:true).appendingPathComponent("\(id)-\(name)") }
    var displaySize:String { ByteCountFormatter.string(fromByteCount:size,countStyle:.file) }
}

@MainActor final class PetFileInbox:ObservableObject {
    static let maxFileSize:Int64=100*1024*1024
    static let maxBatchSize:Int64=250*1024*1024
    static let maxStoredSize:Int64=500*1024*1024
    static let maxBatchFiles=20
    @Published private(set) var files:[PetInboxFile]=[]
    @Published private(set) var message="Drop a file on your buddy to let them catch it."
    private let directory=PetStore.root.appendingPathComponent("PetInbox",isDirectory:true)
    init() { reload() }
    func canAccept(_ urls:[URL])->Bool {
        guard !urls.isEmpty,urls.count<=Self.maxBatchFiles else { return false }
        var total:Int64=0
        for url in urls {
            let values=try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard url.isFileURL,values?.isRegularFile == true,values?.isSymbolicLink != true,let size=values?.fileSize,size>=0,Int64(size)<=Self.maxFileSize else { return false }
            total+=Int64(size); if total>Self.maxBatchSize { return false }
        }
        return true
    }
    @discardableResult func catchFiles(_ urls:[URL]) throws -> Int {
        guard canAccept(urls) else { throw PawError.message("Your pet can catch up to 20 regular files at once, each under 100 MB (250 MB total).") }
        let incoming=urls.reduce(Int64(0)){sum,url in sum+Int64((try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0)}
        guard files.reduce(Int64(0),{$0+$1.size})+incoming<=Self.maxStoredSize,files.count+urls.count<=200 else { throw PawError.message("Your pet’s pocket is full. Remove a few files before dropping more.") }
        if FileManager.default.fileExists(atPath:directory.path) {
            let values=try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isDirectory == true,values.isSymbolicLink != true else { throw PawError.message("The pet’s pocket folder is not a safe directory.") }
        } else { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) }
        var caught=0
        var copied:[URL]=[]
        do {
            for source in urls {
                let id=UUID().uuidString
                let name=Self.safeName(source.lastPathComponent)
                let target=directory.appendingPathComponent("\(id)__\(name)")
                let scoped=source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at:source,to:target)
                copied.append(target)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
                let size=(try target.resourceValues(forKeys:[.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                files.insert(PetInboxFile(id:id,name:name,size:size,added:Date()),at:0)
                caught+=1
            }
            if files.count>200 { for expired in files.dropFirst(200) { try? FileManager.default.removeItem(at:expired.url) }; files=Array(files.prefix(200)) }
            message=caught == 1 ? "Caught \(files[0].name)!" : "Caught \(caught) files!"
            return caught
        } catch {
            copied.forEach{try? FileManager.default.removeItem(at:$0)}
            reload()
            throw PawError.message("Your pet couldn’t store that file: \(error.localizedDescription)")
        }
    }
    func reload() {
        let children=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey,.creationDateKey],options:[.skipsHiddenFiles])) ?? []
        files=children.compactMap { url in
            let leaf=url.lastPathComponent
            guard let split=leaf.range(of:"__") else { return nil }
            let id=String(leaf[..<split.lowerBound]),name=String(leaf[split.upperBound...])
            guard UUID(uuidString:id) != nil,!name.isEmpty,
                  let values=try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey,.creationDateKey]),values.isRegularFile == true,values.isSymbolicLink != true else { return nil }
            return PetInboxFile(id:id,name:name,size:Int64(values.fileSize ?? 0),added:values.creationDate ?? .distantPast)
        }.sorted { $0.added>$1.added }
    }
    func open(_ file:PetInboxFile) { guard FileManager.default.fileExists(atPath:file.url.path) else { reload(); return }; NSWorkspace.shared.open(file.url) }
    func openFolder() {
        do {
            if !FileManager.default.fileExists(atPath:directory.path) { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) }
            NSWorkspace.shared.open(directory)
        } catch { message="Could not open the pocket folder." }
    }
    func reveal(_ file:PetInboxFile) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
    func remove(_ file:PetInboxFile) { try? FileManager.default.removeItem(at:file.url); files.removeAll{$0.id==file.id}; message="Put \(file.name) back." }
    func empty() { for file in files { try? FileManager.default.removeItem(at:file.url) }; files=[]; message="Your pet hasn’t caught anything yet." }
    private static func safeName(_ value:String)->String {
        let clean=value.replacingOccurrences(of:"/",with:"-").replacingOccurrences(of:"\\",with:"-").trimmingCharacters(in:.whitespacesAndNewlines)
        let bounded=String((clean.isEmpty ? "Dropped file" : clean).prefix(160))
        return bounded == "." || bounded == ".." ? "Dropped file" : bounded
    }
}

@MainActor final class PetFileShelfController {
    private let inbox:PetFileInbox
    private weak var petWindow:NSWindow?
    private var panel:NSPanel?
    private var closeTimer:Timer?
    private var eventMonitors:[Any]=[]
    init(inbox:PetFileInbox) {
        self.inbox=inbox
        inbox.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }.store(in:&cancellables)
    }
    private var cancellables=Set<AnyCancellable>()
    func attach(to window:NSWindow) {
        petWindow=window
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching:[.mouseMoved,.leftMouseDown]) { [weak self] event in
            guard let self else { return }
            DispatchQueue.main.async { self.checkPointer(NSEvent.mouseLocation) }
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            self.checkPointer(NSEvent.mouseLocation); return event
        } as Any)
    }
    func show(near window:NSWindow?=nil) {
        if let window { petWindow=window }
        guard let petWindow,let screen=petWindow.screen ?? NSScreen.main else { return }
        closeTimer?.invalidate()
        if panel==nil {
            let created=NSPanel(contentRect:CGRect(x:0,y:0,width:318,height:290),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            created.isOpaque=false;created.backgroundColor = .clear;created.hasShadow=false;created.hidesOnDeactivate=false
            created.isReleasedWhenClosed=false;created.becomesKeyOnlyIfNeeded=true;created.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            created.level = NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-2)
            created.contentView=NSHostingView(rootView:PetFileShelfView(inbox:inbox,onInteraction:{[weak self] in self?.holdOpen()}))
            panel=created
        }
        let visible=screen.visibleFrame,frame=petWindow.frame
        let x=max(visible.minX,min(visible.maxX-318,frame.midX-159))
        let y=max(visible.minY,min(visible.maxY-290,frame.maxY-10))
        panel?.setFrame(CGRect(x:x,y:y,width:318,height:290),display:true)
        panel?.orderFrontRegardless();holdOpen()
    }
    func holdOpen() { closeTimer?.invalidate();closeTimer=nil }
    private func refresh() { if panel?.isVisible == true { panel?.contentView=NSHostingView(rootView:PetFileShelfView(inbox:inbox,onInteraction:{[weak self] in self?.holdOpen()})) } }
    private func checkPointer(_ point:CGPoint) {
        guard let panel,panel.isVisible else { return }
        if panel.frame.insetBy(dx:-12,dy:-12).contains(point) { holdOpen();return }
        if let petWindow,petWindow.frame.insetBy(dx:-20,dy:-20).contains(point) { holdOpen();return }
        guard closeTimer==nil else { return }
        closeTimer=Timer.scheduledTimer(withTimeInterval:1.2,repeats:false) { [weak self] _ in MainActor.assumeIsolated { self?.panel?.orderOut(nil);self?.closeTimer=nil } }
    }
    func stop() { closeTimer?.invalidate();closeTimer=nil;eventMonitors.forEach(NSEvent.removeMonitor);eventMonitors=[];panel?.orderOut(nil);panel?.contentView=nil;panel=nil }
}

private struct PetFileShelfView:View {
    @ObservedObject var inbox:PetFileInbox
    var onInteraction:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:9) {
                Image(systemName:"tray.full.fill").font(.system(size:16,weight:.semibold)).foregroundStyle(Color(red:0.83,green:0.43,blue:0.57))
                VStack(alignment:.leading,spacing:1) { Text("Buddy’s pocket").font(.system(size:14,weight:.bold,design:.rounded));Text("\(inbox.files.count) caught \(inbox.files.count==1 ? "file":"files")").font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(.secondary) }
                Spacer();Button { inbox.openFolder();onInteraction() } label:{Image(systemName:"folder")}.buttonStyle(.plain).help("Open pet’s pocket folder")
            }
            if inbox.files.isEmpty {
                Spacer(minLength:8)
                VStack(spacing:8) { Image(systemName:"shippingbox.fill").font(.system(size:29)).foregroundStyle(Color(red:0.84,green:0.68,blue:0.72));Text("Nothing in my pocket yet!").font(.system(size:12,weight:.semibold,design:.rounded));Text("Drag a file onto me and I’ll catch it.").font(.system(size:10,design:.rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth:.infinity)
                Spacer(minLength:8)
            } else {
                ScrollView {
                    VStack(spacing:5) { ForEach(inbox.files.prefix(8)) { file in
                        HStack(spacing:9) {
                            Image(systemName:"doc.fill").font(.system(size:13)).foregroundStyle(Color(red:0.62,green:0.49,blue:0.70)).frame(width:21)
                            VStack(alignment:.leading,spacing:1){Text(file.name).font(.system(size:10,weight:.semibold,design:.rounded)).lineLimit(1);Text(file.displaySize).font(.system(size:9,design:.rounded)).foregroundStyle(.secondary)}
                            Spacer(minLength:3)
                            Button { inbox.open(file);onInteraction() } label:{Image(systemName:"arrow.up.right.square")}.buttonStyle(.plain).help("Open file")
                            Button { inbox.reveal(file);onInteraction() } label:{Image(systemName:"folder.badge.questionmark")}.buttonStyle(.plain).help("Show in Finder")
                            Button { inbox.remove(file);onInteraction() } label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary)}.buttonStyle(.plain).help("Remove from pocket")
                        }.padding(.horizontal,7).padding(.vertical,5).background(.white.opacity(0.76),in:RoundedRectangle(cornerRadius:11))
                    } }
                }
                if inbox.files.count>8 { Text("\(inbox.files.count-8) more in the pocket folder").font(.system(size:9,design:.rounded)).foregroundStyle(.secondary) }
            }
        }.padding(14).frame(width:318,height:290).background(RoundedRectangle(cornerRadius:25).fill(Color(red:1,green:0.97,blue:0.96))).overlay(RoundedRectangle(cornerRadius:25).stroke(Color(red:0.91,green:0.78,blue:0.80),lineWidth:1.4)).shadow(color:.black.opacity(0.16),radius:12,y:5).onHover{inside in if inside { onInteraction() }}
    }
}
