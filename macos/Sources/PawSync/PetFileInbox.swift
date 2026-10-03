import AppKit
import Combine
import SwiftUI

struct PetInboxFile:Identifiable,Codable,Equatable {
    var id:String
    var name:String
    var size:Int64
    var added:Date
    var idValue:UUID { UUID(uuidString:id) ?? UUID() }
    var url:URL { PetStore.root.appendingPathComponent("PetInbox",isDirectory:true).appendingPathComponent("\(id)__\(name)") }
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
    private var dropTargetActive=false
    private var closeTimer:Timer?
    private var pointerTimer:Timer?
    init(inbox:PetFileInbox) {
        self.inbox=inbox
        inbox.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }.store(in:&cancellables)
    }
    private var cancellables=Set<AnyCancellable>()
    func attach(to window:NSWindow) {
        petWindow=window
    }
    func show(near window:NSWindow?=nil) {
        guard !inbox.files.isEmpty else { return }
        present(near:window)
    }
    func showDropTarget(near window:NSWindow?=nil) {
        dropTargetActive=true
        present(near:window)
    }
    func hideDropTarget() {
        dropTargetActive=false
        if inbox.files.isEmpty { closeTimer?.invalidate(); panel?.orderOut(nil) }
        else { refresh() }
    }
    private func present(near window:NSWindow?=nil) {
        if let window { petWindow=window }
        guard let petWindow,let screen=petWindow.screen ?? NSScreen.main else { return }
        closeTimer?.invalidate()
        if panel==nil {
            let created=PawPopupPanel(contentRect:CGRect(x:0,y:0,width:320,height:242),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            created.isOpaque=false;created.backgroundColor = .clear;created.hasShadow=false;created.hidesOnDeactivate=false
            created.isReleasedWhenClosed=false;created.becomesKeyOnlyIfNeeded=true;created.ignoresMouseEvents=false;created.worksWhenModal=true;created.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            created.level = .floating
            let host=NSHostingView(rootView:PetFileShelfView(inbox:inbox,dropTarget:dropTargetActive,onClose:{[weak self] in self?.dismiss()},onInteraction:{[weak self] in self?.holdOpen()}))
            created.contentView=host
            panel=created
        }
        let visible=screen.visibleFrame,frame=petWindow.frame
        let x=max(visible.minX,min(visible.maxX-320,frame.midX-160))
        let y=max(visible.minY,min(visible.maxY-242,frame.maxY-12))
        panel?.setFrame(CGRect(x:x,y:y,width:320,height:242),display:true)
        panel?.ignoresMouseEvents=dropTargetActive && inbox.files.isEmpty
        if let panel,let host=panel.contentView as? NSHostingView<PetFileShelfView> {
            host.rootView=PetFileShelfView(inbox:inbox,dropTarget:dropTargetActive,onClose:{[weak self] in self?.dismiss()},onInteraction:{[weak self] in self?.holdOpen()})
        }
        panel?.orderFrontRegardless();holdOpen()
        if pointerTimer == nil { pointerTimer=Timer.scheduledTimer(withTimeInterval:0.22,repeats:true){[weak self] _ in MainActor.assumeIsolated { guard let self else { return };self.checkPointer(NSEvent.mouseLocation) } } }
    }
    func holdOpen() { closeTimer?.invalidate();closeTimer=nil }
    func dismiss() { closeTimer?.invalidate();closeTimer=nil;pointerTimer?.invalidate();pointerTimer=nil;panel?.orderOut(nil) }
    private func refresh() {
        guard panel?.isVisible == true else { return }
        guard !inbox.files.isEmpty || dropTargetActive else { dismiss();return }
        if let panel,let host=panel.contentView as? NSHostingView<PetFileShelfView> {
            host.rootView=PetFileShelfView(inbox:inbox,dropTarget:dropTargetActive,onClose:{[weak self] in self?.dismiss()},onInteraction:{[weak self] in self?.holdOpen()})
        }
        panel?.ignoresMouseEvents=dropTargetActive && inbox.files.isEmpty
    }
    private func checkPointer(_ point:CGPoint) {
        guard let panel,panel.isVisible else { return }
        if panel.frame.insetBy(dx:-12,dy:-12).contains(point) { holdOpen();return }
        if let petWindow,petWindow.frame.insetBy(dx:-20,dy:-20).contains(point) { holdOpen();return }
        guard closeTimer==nil else { return }
        closeTimer=Timer.scheduledTimer(withTimeInterval:0.72,repeats:false) { [weak self] _ in MainActor.assumeIsolated { guard let self,self.panel?.isVisible == true else { return };self.closeTimer=nil;let current=NSEvent.mouseLocation;if !(self.panel?.frame.insetBy(dx:-8,dy:-8).contains(current) ?? false) && !(self.petWindow?.frame.insetBy(dx:-18,dy:-18).contains(current) ?? false) { self.dismiss() } } }
    }
    func stop() { closeTimer?.invalidate();closeTimer=nil;pointerTimer?.invalidate();pointerTimer=nil;panel?.orderOut(nil);panel?.contentView=nil;panel=nil }
}

private struct PetFileShelfView:View {
    @ObservedObject var inbox:PetFileInbox
    var dropTarget:Bool
    var onClose:()->Void
    var onInteraction:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            if dropTarget && inbox.files.isEmpty {
                Spacer(minLength:12)
                VStack(spacing:10) {
                    ZStack { Circle().fill(Color(red:0.98,green:0.83,blue:0.75)).frame(width:54,height:54);Image(systemName:"tray.and.arrow.down.fill").font(.system(size:22,weight:.semibold)).foregroundStyle(Color(red:0.63,green:0.38,blue:0.38)) }
                    Text("A little something for me?").font(.system(size:15,weight:.bold,design:.rounded))
                    Text("Drop your file here and I’ll tuck it away.").font(.system(size:11,weight:.medium,design:.rounded)).foregroundStyle(Color(red:0.48,green:0.40,blue:0.40))
                }.frame(maxWidth:.infinity)
                Spacer(minLength:12)
            } else {
            HStack(spacing:10) {
                ZStack { Circle().fill(Color(red:0.98,green:0.85,blue:0.78)).frame(width:36,height:36);Image(systemName:"pawprint.fill").font(.system(size:16,weight:.semibold)).foregroundStyle(Color(red:0.73,green:0.42,blue:0.48)) }
                VStack(alignment:.leading,spacing:2) { Text("My little stash").font(.system(size:15,weight:.bold,design:.rounded));Text("\(inbox.files.count) saved \(inbox.files.count==1 ? "file":"files")").font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(Color(red:0.48,green:0.40,blue:0.40)) }
                Spacer()
                Button { inbox.openFolder();onInteraction() } label:{Image(systemName:"folder")}.buttonStyle(PouchIconButtonStyle()).help("Open saved files")
                Button(action:onClose){Image(systemName:"xmark").font(.system(size:10,weight:.bold))}.buttonStyle(PouchIconButtonStyle()).help("Close pocket")
            }.padding(.bottom,3)
                ScrollView {
                    VStack(spacing:7) { ForEach(inbox.files.prefix(6)) { file in fileRow(file) } }
                }
                if inbox.files.count>6 { Text("+\(inbox.files.count-6) more in your folder").font(.system(size:9,design:.rounded)).foregroundStyle(.secondary).padding(.leading,8) }
            }
        }.padding(.horizontal,15).padding(.top,24).padding(.bottom,14).frame(width:320,height:242)
            .background { ZStack(alignment:.top) {
                Capsule().stroke(Color(red:0.73,green:0.53,blue:0.48),lineWidth:5).frame(width:78,height:35).offset(y:1)
                RoundedRectangle(cornerRadius:25,style:.continuous).fill(Color(red:1,green:0.95,blue:0.86)).padding(.top,17)
                RoundedRectangle(cornerRadius:25,style:.continuous).stroke(dropTarget ? Color(red:0.82,green:0.40,blue:0.57) : Color(red:0.79,green:0.64,blue:0.56),style:StrokeStyle(lineWidth:dropTarget ? 2.2 : 1.4,dash:dropTarget ? [6,4] : [])).padding(.top,17)
                Capsule().fill(Color(red:0.96,green:0.84,blue:0.71)).frame(width:92,height:18).overlay(Circle().fill(Color(red:0.77,green:0.53,blue:0.48)).frame(width:7,height:7)).padding(.top,20)
            }}.shadow(color:Color(red:0.43,green:0.31,blue:0.28).opacity(0.20),radius:12,y:6).onHover{inside in if inside { onInteraction() }}
    }
    private func fileRow(_ file:PetInboxFile)->some View {
        HStack(spacing:8) {
            Image(systemName:"doc.text.fill").font(.system(size:14)).foregroundStyle(Color(red:0.63,green:0.47,blue:0.63)).frame(width:29,height:32).background(Color(red:1,green:0.94,blue:0.87),in:RoundedRectangle(cornerRadius:9))
            VStack(alignment:.leading,spacing:2) {
                Text(file.name).font(.system(size:10,weight:.semibold,design:.rounded)).lineLimit(1)
                Text(file.displaySize).font(.system(size:9,design:.rounded)).foregroundStyle(.secondary)
            }
            Spacer(minLength:2)
            Button { inbox.open(file);onInteraction() } label:{Image(systemName:"arrow.up.right")}.buttonStyle(.plain).help("Open file")
            Button { inbox.reveal(file);onInteraction() } label:{Image(systemName:"folder")}.buttonStyle(.plain).help("Show in Finder")
            Button { inbox.remove(file);onInteraction() } label:{Image(systemName:"xmark").foregroundStyle(.secondary)}.buttonStyle(.plain).help("Remove from pocket")
        }
        .padding(.horizontal,9).padding(.vertical,7).background(Color.white,in:RoundedRectangle(cornerRadius:15,style:.continuous)).overlay(RoundedRectangle(cornerRadius:15,style:.continuous).stroke(Color(red:0.92,green:0.85,blue:0.79),lineWidth:0.8)).contentShape(RoundedRectangle(cornerRadius:15,style:.continuous))
        .onDrag { NSItemProvider(contentsOf:file.url) ?? NSItemProvider(object:file.url as NSURL) }
    }
}

private struct PouchIconButtonStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View { configuration.label.font(.system(size:11,weight:.semibold)).foregroundStyle(Color(red:0.49,green:0.37,blue:0.38)).frame(width:27,height:27).background(Color.white,in:Circle()).overlay(Circle().stroke(Color(red:0.90,green:0.82,blue:0.77),lineWidth:0.8)).scaleEffect(configuration.isPressed ? 0.92:1) }
}
