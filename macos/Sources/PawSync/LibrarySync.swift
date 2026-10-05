import Foundation
import Combine
import AppKit
import ServiceManagement

@MainActor final class LibrarySyncService:ObservableObject {
    @Published private(set) var status="Progress stays on this Mac."
    @Published private(set) var busy=false
    @Published private(set) var lastSync:Date?
    var onMerged:((LibrarySnapshot)->Void)?
    private var stopped=false
    private let library:LibraryProgress
    private let api:APIClient
    private var pending:DispatchWorkItem?,periodic:Timer?
    init(library:LibraryProgress,api:APIClient) {
        self.library=library;self.api=api
        periodic=Timer.scheduledTimer(withTimeInterval:300,repeats:true){[weak self] _ in Task{@MainActor in await self?.sync()}};periodic?.tolerance=30
    }
    func changed() {
        guard library.state.syncEnabled,!busy,pending==nil else{return}
        let work=DispatchWorkItem{[weak self] in self?.pending=nil;Task{@MainActor in await self?.sync()}};pending=work;DispatchQueue.main.asyncAfter(deadline:.now()+45,execute:work)
    }
    func setEnabled(_ enabled:Bool) {library.updateOptions(sync:enabled);if enabled{Task{await sync()}}else{pending?.cancel();pending=nil;status="Progress stays on this Mac."}}
    func sync() async {
        guard library.state.syncEnabled,!busy,!stopped else{return}
        guard KeychainStore.read("license") != nil else{status="Restore your purchase in Account to sync progress. Local play still works.";return}
        busy=true;defer{busy=false}
        do{
            let data=try await api.request("v1/library/progress",method:"POST",body:JSONEncoder().encode(library.export()))
            let remote=try JSONDecoder().decode(LibrarySnapshot.self,from:data);guard !stopped else{return};try library.merge(remote);onMerged?(library.state)
            lastSync=Date();status="All together. Latest progress is saved on this Mac and in your account."
        }catch{status="Sync will retry later. Your local progress is safe. \(error.localizedDescription)"}
    }
    func resetProgress() async throws {
        guard !busy else{throw PawError.message("Wait for the current sync to finish, then try again.")}
        busy=true;defer{busy=false}
        if library.state.syncEnabled {
            let result=try await api.request("v1/library/progress/reset",method:"POST")
            struct Reset:Decodable {let epoch:Int}
            let response=try JSONDecoder().decode(Reset.self,from:result)
            try library.reset(epoch:response.epoch)
        }else{try library.reset()}
        status=library.state.syncEnabled ? "Progress reset on this Mac and your account. Purchases and settings are unchanged.":"Progress reset. Purchases and settings are unchanged."
    }
    func stop(){stopped=true;pending?.cancel();periodic?.invalidate()}
}

@MainActor enum LoginLaunch {
    static var enabled:Bool {SMAppService.mainApp.status == .enabled}
    static func set(_ enabled:Bool) throws {if enabled {try SMAppService.mainApp.register()}else{try SMAppService.mainApp.unregister()}}
}

@MainActor final class LibraryToast {
    private var panel:NSPanel?
    private var expiry:DispatchWorkItem?
    func show(_ title:String,subtitle:String,icon:String) {
        expiry?.cancel();panel?.close()
        let p=NSPanel(contentRect:CGRect(x:0,y:0,width:340,height:88),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isReleasedWhenClosed=false;p.level = .floating;p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.ignoresMouseEvents=true;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        p.contentView=NSHostingView(rootView:LibraryToastView(title:title,subtitle:subtitle,icon:icon))
        let screen=NSScreen.screens.first{$0.frame.contains(NSEvent.mouseLocation)} ?? NSScreen.main
        if let screen{p.setFrameOrigin(CGPoint(x:screen.visibleFrame.maxX-365,y:screen.visibleFrame.maxY-112))}
        p.orderFrontRegardless();panel=p
        let work=DispatchWorkItem{[weak self] in self?.panel?.close();self?.panel=nil};expiry=work;DispatchQueue.main.asyncAfter(deadline:.now()+4,execute:work)
    }
    func stop(){expiry?.cancel();panel?.close();panel=nil}
}

import SwiftUI
private struct LibraryToastView:View {
    let title:String,subtitle:String,icon:String
    var body:some View{HStack(spacing:14){Image(systemName:icon).font(.system(size:27)).foregroundStyle(LibraryStyle.purple).frame(width:54,height:54).background(LibraryStyle.purple.opacity(0.09),in:Circle());VStack(alignment:.leading,spacing:5){Text(subtitle).font(.system(size:11,weight:.medium)).foregroundStyle(LibraryStyle.muted);Text(title).font(.system(size:16,weight:.bold,design:.rounded)).foregroundStyle(LibraryStyle.ink)};Spacer()}.padding(15).background(LibraryStyle.paper,in:RoundedRectangle(cornerRadius:24)).overlay(RoundedRectangle(cornerRadius:24).stroke(LibraryStyle.purple.opacity(0.16)))}
}
