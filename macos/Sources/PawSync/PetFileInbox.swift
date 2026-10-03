import AppKit
import Combine
import UniformTypeIdentifiers

/// A session-only reference. PawSync never copies, renames, moves or deletes it.
struct PetInboxFile:Identifiable,Equatable {
    let id:String
    let name:String
    let size:Int64
    let added:Date
    let url:URL
    var displaySize:String { ByteCountFormatter.string(fromByteCount:size,countStyle:.file) }
}

@MainActor final class PetFileInbox:ObservableObject {
    static let maxBatchFiles=20
    static let maxHeldFiles=200
    @Published private(set) var files:[PetInboxFile]=[]
    @Published private(set) var message="Drop a file on your buddy for a temporary helping paw."
    private var scopedURLs:[String:URL]=[:]
    // Earlier versions made persistent copies. Leave those recoverable, but do
    // not load them into this session's pocket or delete somebody's only copy.
    private let legacyDirectory:URL
    init(legacyDirectory:URL=PetStore.root.appendingPathComponent("PetInbox",isDirectory:true)) { self.legacyDirectory=legacyDirectory }
    deinit { scopedURLs.values.forEach { $0.stopAccessingSecurityScopedResource() } }
    var hasEarlierCopies:Bool {
        let entries=(try? FileManager.default.contentsOfDirectory(at:legacyDirectory,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles])) ?? []
        return entries.contains { $0.lastPathComponent.contains("__") }
    }
    func showEarlierCopies() { NSWorkspace.shared.open(legacyDirectory) }
    func canAccept(_ urls:[URL])->Bool {
        guard !urls.isEmpty,urls.count<=Self.maxBatchFiles else { return false }
        return urls.allSatisfy { url in
            guard url.isFileURL else { return false }
            let values=try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true
        }
    }
    func canAcceptDrop(_ urls:[URL])->Bool {
        let held=Set(files.map { $0.url.standardizedFileURL.path })
        return canAccept(urls) && urls.contains { !held.contains($0.standardizedFileURL.path) }
    }
    @discardableResult func catchFiles(_ urls:[URL]) throws -> Int {
        guard canAccept(urls) else { throw PawError.message("Your pet can hold up to 20 regular files at a time. The originals stay where they are.") }
        reload()
        var paths=Set(files.map { $0.url.standardizedFileURL.path })
        let incoming=urls.filter { paths.insert($0.standardizedFileURL.path).inserted }
        guard files.count+incoming.count<=Self.maxHeldFiles else { throw PawError.message("Your pet’s paws are full. Release a few files before dropping more.") }
        var received:[PetInboxFile]=[]
        var scoped:[String:URL]=[:]
        do {
            for source in incoming {
                let id=UUID().uuidString
                if source.startAccessingSecurityScopedResource() { scoped[id]=source }
                let values=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard values.isRegularFile == true,values.isSymbolicLink != true else { throw PawError.message("That file is no longer available.") }
                received.append(PetInboxFile(id:id,name:source.lastPathComponent,size:Int64(values.fileSize ?? 0),added:Date(),url:source))
            }
        } catch {
            scoped.values.forEach { $0.stopAccessingSecurityScopedResource() }
            throw PawError.message("Your pet couldn’t hold that file: \(error.localizedDescription)")
        }
        scopedURLs.merge(scoped) { _,new in new }
        files.insert(contentsOf:received.reversed(),at:0)
        message=received.isEmpty ? "Already in my paws!" : received.count == 1 ? "Holding \(received[0].name) for now!" : "Holding \(received.count) files for now!"
        return received.count
    }
    /// Refresh availability, never restore a saved shelf after restarting.
    func reload() {
        let missing=files.filter { !FileManager.default.fileExists(atPath:$0.url.path) }
        for file in missing { release(file.id) }
    }
    func open(_ file:PetInboxFile) {
        guard FileManager.default.fileExists(atPath:file.url.path) else { reload();message="The original file is no longer there.";return }
        NSWorkspace.shared.open(file.url)
    }
    func showOriginals() { NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url)) }
    func reveal(_ file:PetInboxFile) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
    func remove(_ file:PetInboxFile) { release(file.id);message="Released \(file.name). Your original is untouched." }
    func finishDrag(_ file:PetInboxFile,operation:NSDragOperation) {
        guard !operation.intersection([.copy,.move,.link]).isEmpty else { return }
        remove(file)
    }
    private func release(_ id:String) {
        scopedURLs.removeValue(forKey:id)?.stopAccessingSecurityScopedResource()
        files.removeAll { $0.id == id }
    }
    func empty() {
        scopedURLs.values.forEach { $0.stopAccessingSecurityScopedResource() };scopedURLs.removeAll()
        files=[];message="Your pet’s paws are free. Your originals are untouched."
    }
}

@MainActor final class PetFileShelfController {
    private let inbox:PetFileInbox
    private weak var petWindow:NSWindow?
    private var panel:PawPopupPanel?
    private var dropTargetActive=false
    private var draggingOut=false
    private var pointerTimer:Timer?
    private var lastInside=Date()
    private var cancellables=Set<AnyCancellable>()
    var isVisible:Bool { panel?.isVisible == true }
    var attachment:(()->PetChromeAnchor)?
    var onFileDrop:(([URL])->Bool)?
    var onReceivingFiles:((Bool)->Void)?
    init(inbox:PetFileInbox) {
        self.inbox=inbox
        inbox.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }.store(in:&cancellables)
    }
    func attach(to window:NSWindow) { petWindow=window }
    func show(near window:NSWindow?=nil) { guard !inbox.files.isEmpty else { return };if isVisible { holdOpen();return };present(near:window) }
    func showDropTarget(near window:NSWindow?=nil) { dropTargetActive=true;present(near:window) }
    func hideDropTarget() { dropTargetActive=false;if inbox.files.isEmpty { if !(panel?.frame.contains(NSEvent.mouseLocation) ?? false) { dismiss() } } else { refresh() } }
    private func present(near window:NSWindow?=nil) {
        if let window { petWindow=window }
        guard let petWindow else { return }
        if panel == nil {
            let p=PawPopupPanel(contentRect:CGRect(x:0,y:0,width:300,height:250),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.title="PawSync Pet Pocket";p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
            p.becomesKeyOnlyIfNeeded=true;p.ignoresMouseEvents=false;p.worksWhenModal=true;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle];p.level=NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-1);panel=p
        }
        let context=attachment?() ?? .fallback(petWindow)
        // A little pouch hangs beside the companion's paws, not over its face.
        let roomOnLeft=context.pet.minX-context.visible.minX
        let x=roomOnLeft >= 292 ? context.pet.minX-300+8 : context.pet.maxX-8
        panel?.setFrame(context.clamp(CGRect(x:x,y:context.pet.minY-12,width:300,height:250)),display:true)
        refreshContent(context:context);panel?.ignoresMouseEvents=false;panel?.orderFrontRegardless();holdOpen()
        if pointerTimer == nil {
            let timer=Timer(timeInterval:0.12,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.checkPointer() } }
            timer.tolerance=0.03;RunLoop.main.add(timer,forMode:.common);pointerTimer=timer
        }
    }
    private func refreshContent(context:PetChromeAnchor) {
        panel?.contentView=PetPocketNativeView(files:inbox.files,dropTarget:dropTargetActive,palette:context.palette,name:context.name,onOpen:{[weak self] file in self?.inbox.open(file);self?.holdOpen()},onRemove:{[weak self] file in self?.inbox.remove(file);self?.holdOpen()},onFolder:{[weak self] in self?.inbox.showOriginals()},onClose:{[weak self] in self?.dismiss()},onDrop:{[weak self] urls in self?.onFileDrop?(urls) ?? false},canDrop:{[weak self] urls in self?.inbox.canAcceptDrop(urls) ?? false},onReceiving:{[weak self] active in self?.onReceivingFiles?(active);self?.holdOpen()},onDragging:{[weak self] active in self?.draggingOut=active;self?.holdOpen()},onDragCompleted:{[weak self] file,operation in self?.inbox.finishDrag(file,operation:operation)},onClear:{[weak self] in self?.inbox.empty()})
    }
    func holdOpen() { lastInside=Date() }
    func dismiss() { guard !draggingOut else { return };pointerTimer?.invalidate();pointerTimer=nil;panel?.orderOut(nil) }
    private func refresh() {
        guard let panel,panel.isVisible,let petWindow else { return }
        guard !inbox.files.isEmpty || dropTargetActive else { dismiss();return }
        guard !draggingOut else { return }
        refreshContent(context:attachment?() ?? .fallback(petWindow))
    }
    private func checkPointer() {
        guard let panel,panel.isVisible else { return }
        guard !draggingOut,!dropTargetActive else { holdOpen();return }
        if inbox.files.isEmpty { dismiss();return }
        let cursor=NSEvent.mouseLocation
        let pet=attachment?().pet ?? petWindow?.frame ?? .zero
        if panel.frame.insetBy(dx:-10,dy:-10).contains(cursor) || pet.insetBy(dx:-14,dy:-14).contains(cursor) { holdOpen() }
        else if Date().timeIntervalSince(lastInside)>0.65 { dismiss() }
    }
    func stop() { draggingOut=false;dismiss();panel?.contentView=nil;panel=nil }
}

@MainActor final class PetPocketNativeView:NSView {
    let palette:PetChromePalette
    private let files:[PetInboxFile]
    private let dropTarget:Bool
    private let onDrop:([URL])->Bool
    private let canDrop:([URL])->Bool
    private let onDragging:(Bool)->Void
    private let onReceiving:(Bool)->Void
    init(files:[PetInboxFile],dropTarget:Bool,palette:PetChromePalette,name:String,onOpen:@escaping (PetInboxFile)->Void,onRemove:@escaping (PetInboxFile)->Void,onFolder:@escaping ()->Void,onClose:@escaping ()->Void,onDrop:@escaping ([URL])->Bool,canDrop:@escaping ([URL])->Bool,onReceiving:@escaping (Bool)->Void={_ in},onDragging:@escaping (Bool)->Void,onDragCompleted:@escaping (PetInboxFile,NSDragOperation)->Void={_,_ in},onClear:@escaping ()->Void={}) {
        self.files=files;self.dropTarget=dropTarget;self.palette=palette;self.onDrop=onDrop;self.canDrop=canDrop;self.onDragging=onDragging;self.onReceiving=onReceiving
        super.init(frame:CGRect(x:0,y:0,width:300,height:250));registerForDraggedTypes([.fileURL])
        if !files.isEmpty {
            let heading=NSTextField(labelWithString:"\(name)’s pocket");heading.font = .systemFont(ofSize:14,weight:.semibold);heading.textColor=palette.ink;heading.frame=CGRect(x:29,y:58,width:195,height:20);addSubview(heading)
            for (title,symbol,x,action) in [("Show originals in Finder","folder",CGFloat(224),onFolder),("Close pocket","xmark",CGFloat(253),onClose)] {
                let b=PetSoftButton(title:"",symbol:symbol,action:action);b.palette=palette;b.frame=CGRect(x:x,y:56,width:24,height:24);b.setAccessibilityLabel(title);addSubview(b)
            }
            let scroll=NSScrollView(frame:CGRect(x:26,y:89,width:250,height:121));scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.borderType = .noBorder;scroll.contentView.drawsBackground=false
            let document=PetPocketRowsView(frame:CGRect(x:0,y:0,width:248,height:CGFloat(files.count)*48))
            for (index,file) in files.enumerated() {
                let row=PetPocketFileRow(file:file,palette:palette,onOpen:{onOpen(file)},onRemove:{onRemove(file)},onDragging:onDragging,onDragCompleted:{operation in onDragCompleted(file,operation)})
                row.frame=CGRect(x:index.isMultiple(of:2) ? 0:3,y:CGFloat(index)*48,width:242,height:44);document.addSubview(row)
            }
            scroll.documentView=document;addSubview(scroll)
            let clear=PetSoftButton(title:"Clear all",action:onClear);clear.palette=palette;clear.emphasis = .primary;clear.frame=CGRect(x:29,y:212,width:72,height:23);clear.setAccessibilityLabel("Clear all held files");clear.toolTip="Release every held file. Your originals stay untouched.";addSubview(clear)
        }
        setAccessibilityLabel("Companion file pocket")
    }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    override var isFlipped:Bool { true }
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        // Two curved straps and fur-colored paws clutch an open, stitched pouch.
        let strap=NSBezierPath();strap.move(to:CGPoint(x:72,y:46));strap.curve(to:CGPoint(x:228,y:46),controlPoint1:CGPoint(x:100,y:4),controlPoint2:CGPoint(x:200,y:4));strap.lineWidth=5;palette.ink.withAlphaComponent(0.65).setStroke();strap.stroke()
        PetChromeDrawing.pocket(in:CGRect(x:13,y:39,width:274,height:203),palette:palette)
        PetChromeDrawing.mitten(in:CGRect(x:57,y:26,width:34,height:29),palette:palette)
        PetChromeDrawing.mitten(in:CGRect(x:209,y:26,width:34,height:29),palette:palette)
        if files.isEmpty {
            PetChromeDrawing.paw(in:CGRect(x:125,y:76,width:50,height:50),palette:palette,pressed:true)
            PetChromeDrawing.label("I’ll catch it!",in:CGRect(x:35,y:139,width:230,height:22),size:16,color:palette.ink,weight:.semibold)
            PetChromeDrawing.label("Drop your file on me or my pocket.",in:CGRect(x:25,y:171,width:250,height:19),size:10,color:palette.ink)
        } else {
            PetChromeDrawing.label("Drag out to release",in:CGRect(x:112,y:209,width:159,height:15),size:9,color:palette.ink.withAlphaComponent(0.85),alignment:.left)
            PetChromeDrawing.label("Temporary · originals stay put",in:CGRect(x:112,y:224,width:159,height:13),size:8,color:palette.ink.withAlphaComponent(0.75),alignment:.left)
        }
    }
    private func urls(_ info:any NSDraggingInfo)->[URL] { (info.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [NSURL] ?? []).map{$0 as URL} }
    override func draggingEntered(_ sender:any NSDraggingInfo)->NSDragOperation { guard canDrop(urls(sender)) else { return [] };onReceiving(true);return .copy }
    override func draggingUpdated(_ sender:any NSDraggingInfo)->NSDragOperation { guard canDrop(urls(sender)) else { onReceiving(false);return [] };onReceiving(true);return .copy }
    override func draggingExited(_ sender:(any NSDraggingInfo)?) { onReceiving(false) }
    override func draggingEnded(_ sender:any NSDraggingInfo) { onReceiving(false) }
    override func prepareForDragOperation(_ sender:any NSDraggingInfo)->Bool { canDrop(urls(sender)) }
    override func performDragOperation(_ sender:any NSDraggingInfo)->Bool { defer { onReceiving(false) };return onDrop(urls(sender)) }
}

@MainActor private final class PetPocketRowsView:NSView { override var isFlipped:Bool { true } }

@MainActor final class PetPocketFileRow:NSView,NSDraggingSource {
    let file:PetInboxFile
    let palette:PetChromePalette
    private let onOpen:()->Void
    private let onDragging:(Bool)->Void
    private let onDragCompleted:(NSDragOperation)->Void
    private var downPoint:CGPoint?
    private var dragging=false
    init(file:PetInboxFile,palette:PetChromePalette,onOpen:@escaping ()->Void,onRemove:@escaping ()->Void,onDragging:@escaping (Bool)->Void,onDragCompleted:@escaping (NSDragOperation)->Void={_ in}) {
        self.file=file;self.palette=palette;self.onOpen=onOpen;self.onDragging=onDragging;self.onDragCompleted=onDragCompleted;super.init(frame:CGRect(x:0,y:0,width:242,height:44))
        let remove=PetSoftButton(title:"",symbol:"xmark",action:onRemove);remove.palette=palette;remove.frame=CGRect(x:216,y:12,width:20,height:20);remove.setAccessibilityLabel("Remove \(file.name) from pocket");addSubview(remove)
        setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("\(file.name), \(file.displaySize). Drag out or double-click to open.")
    }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    override var isFlipped:Bool { true }
    override var needsPanelToBecomeKey:Bool { false }
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        let paper=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:5,yRadius:5)
        PetChromeDrawing.paint(paper,fill:NSColor(calibratedRed:1,green:0.98,blue:0.92,alpha:1),ink:palette.ink.withAlphaComponent(0.25),width:0.8)
        NSWorkspace.shared.icon(forFile:file.url.path).draw(in:CGRect(x:9,y:9,width:24,height:26))
        PetChromeDrawing.label(file.name,in:CGRect(x:41,y:8,width:168,height:16),size:10,color:palette.ink,weight:.semibold,alignment:.left)
        PetChromeDrawing.label(file.displaySize,in:CGRect(x:41,y:25,width:162,height:12),size:9,color:palette.ink.withAlphaComponent(0.64),alignment:.left)
    }
    override func mouseDown(with event:NSEvent) { downPoint=convert(event.locationInWindow,from:nil);dragging=false;if event.clickCount == 2 { onOpen();downPoint=nil } }
    override func mouseDragged(with event:NSEvent) {
        let point=convert(event.locationInWindow,from:nil)
        guard let downPoint,!dragging,hypot(point.x-downPoint.x,point.y-downPoint.y)>4,FileManager.default.fileExists(atPath:file.url.path) else { return }
        dragging=true;onDragging(true)
        let item=NSDraggingItem(pasteboardWriter:file.url as NSURL)
        item.setDraggingFrame(CGRect(x:point.x-16,y:point.y-16,width:32,height:32),contents:NSWorkspace.shared.icon(forFile:file.url.path))
        beginDraggingSession(with:[item],event:event,source:self)
    }
    override func mouseUp(with event:NSEvent) { downPoint=nil }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation { .copy }
    func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) { dragging=false;downPoint=nil;onDragging(false);onDragCompleted(operation) }
}
