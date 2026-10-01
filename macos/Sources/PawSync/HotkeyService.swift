import AppKit
import Carbon
import Combine

enum PetShortcut:String,CaseIterable,Identifiable {
    case off="Off", option="⌘⌥P", shift="⌘⇧P"
    var id:String { rawValue }
    var modifiers:UInt32 { self == .option ? UInt32(cmdKey|optionKey) : UInt32(cmdKey|shiftKey) }
}
@MainActor final class HotkeyService:ObservableObject {
    @Published private(set) var selection:PetShortcut = .off
    @Published private(set) var error=""
    var onToggle:(()->Void)?
    private var hotkey:EventHotKeyRef?
    private var handler:EventHandlerRef?
    private var serial:UInt32=0
    init() {
        var event=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let callback:EventHandlerUPP = { _,_,pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            // A registered command trigger only; no keyboard event contents are read.
            MainActor.assumeIsolated { Unmanaged<HotkeyService>.fromOpaque(pointer).takeUnretainedValue().onToggle?() }
            return noErr
        }
        let result=InstallEventHandler(GetApplicationEventTarget(),callback,1,&event,Unmanaged.passUnretained(self).toOpaque(),&handler)
        if result == noErr { set(PetShortcut(rawValue:UserDefaults.standard.string(forKey:"showHideShortcut") ?? "") ?? .off) }
        else { error="Global shortcut registration is unavailable." }
    }
    func set(_ requested:PetShortcut) {
        guard requested != selection else { return }
        if requested == .off { if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey=nil; selection = .off; error=""; UserDefaults.standard.set(selection.rawValue,forKey:"showHideShortcut"); return }
        guard handler != nil else { error="Global shortcut registration is unavailable."; return }
        serial+=1; var replacement:EventHotKeyRef?
        let result=RegisterEventHotKey(UInt32(kVK_ANSI_P),requested.modifiers,EventHotKeyID(signature:0x50535743,id:serial),GetApplicationEventTarget(),0,&replacement)
        guard result == noErr,let replacement else { error="This shortcut is already in use. Your previous shortcut was kept."; return }
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey=replacement; selection=requested; error=""; UserDefaults.standard.set(selection.rawValue,forKey:"showHideShortcut")
    }
    func stop() { if let hotkey { UnregisterEventHotKey(hotkey) }; if let handler { RemoveEventHandler(handler) }; hotkey=nil; handler=nil }
}
