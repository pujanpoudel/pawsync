import SwiftUI
import AppKit

struct PresentationSettingsView: View {
    @ObservedObject var model:AppModel
    @ObservedObject var store:PetPresentationStore
    @ObservedObject var reactions:ReactionSettings
    @ObservedObject var preferences:Preferences
    @ObservedObject var shortcuts:HotkeyService
    private var id:String { preferences.companion }
    private func hat(_ key:WritableKeyPath<HatTransform,Double>) -> Binding<Double> {
        Binding(get:{ (store.state.hats[id] ?? HatTransform())[keyPath:key] },set:{ value in var transform=store.state.hats[id] ?? HatTransform(); transform[keyPath:key]=value; store.state.hats[id]=transform })
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            GroupBox("Pet & bubble appearance") {
                VStack(alignment:.leading,spacing:12) {
                    Toggle("Flip this pet horizontally",isOn:Binding(get:{store.state.flipped[id] ?? false},set:{store.state.flipped[id]=$0}))
                    Picker("Show / hide shortcut",selection:Binding(get:{shortcuts.selection},set:{shortcuts.set($0)})) { ForEach(PetShortcut.allCases) { Text($0.rawValue).tag($0) } }
                    if !shortcuts.error.isEmpty { Text(shortcuts.error).font(.caption).foregroundStyle(.red) }
                    HStack { Text("Bubble & label size"); Slider(value:$store.state.hudScale,in:0.7...1.5); Text("\(Int(store.state.hudScale*100))%").monospacedDigit().frame(width:45) }
                    DisclosureGroup("Adjust your hat") {
                        HStack { Text("Left / right").frame(width:100,alignment:.leading); Slider(value:hat(\.x),in:-100...100) }
                        HStack { Text("Up / down").frame(width:100,alignment:.leading); Slider(value:hat(\.y),in:-100...100) }
                        HStack { Text("Size").frame(width:100,alignment:.leading); Slider(value:hat(\.scale),in:0.4...2) }
                        HStack { Text("Tilt").frame(width:100,alignment:.leading); Slider(value:hat(\.rotation),in:-90...90) }
                        Button("Reset placement") { store.state.hats[id]=HatTransform() }
                    }
                    Menu("Temporarily hide around an app") {
                        ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier },id: \.processIdentifier) { app in
                            if let bundle=app.bundleIdentifier { Button(app.localizedName ?? bundle) { if !store.state.hideInApps.contains(bundle),store.state.hideInApps.count < 100 { store.state.hideInApps.append(bundle) } } }
                        }
                    }
                    HStack { Text("Walk speed"); Slider(value:Binding(get:{store.state.walkSpeed ?? 95},set:{store.state.walkSpeed=$0}),in:20...200); Text("\(Int(store.state.walkSpeed ?? 95)) px/s").font(.caption).frame(width:60) }
                    HStack { Text("Roam interval"); Slider(value:Binding(get:{store.state.wanderInterval ?? 25},set:{store.state.wanderInterval=$0}),in:3...120); Text("\(Int(store.state.wanderInterval ?? 25)) s").font(.caption).frame(width:60) }
                    Text("Temporary hiding preserves your manual Show / Hide choice.").font(.caption).foregroundStyle(.secondary)
                    ForEach(store.state.hideInApps,id:\.self) { bundle in HStack { Text(bundle).font(.caption); Spacer(); Button("Stop hiding") { store.state.hideInApps.removeAll{$0 == bundle} } } }
                    if !store.error.isEmpty { Text(store.error).foregroundStyle(.red) }
                }.padding(8)
            }
            GroupBox("Reaction animations") {
                VStack(alignment:.leading,spacing:10) {
                    Toggle("Relaxed waiting rhythm",isOn:$reactions.relaxedWaiting)
                    ForEach(PetReaction.allCases) { reaction in
                        HStack {
                            Text(reaction.rawValue.capitalized).frame(width:85,alignment:.leading)
                            Picker("Animation for \(reaction.rawValue)",selection:Binding(get:{reactions.animation(for:reaction)},set:{reactions.mapping[reaction.rawValue]=$0})) { ForEach(PetAnimation.allCases) { animation in Text(animation.rawValue.capitalized).tag(animation) } }.labelsHidden()
                            Button("Preview") { model.previewReaction(reaction) }
                        }
                    }
                    HStack { Button("Return to idle") { model.previewReaction(.idle) }; Button("Restore mappings") { reactions.restore() } }
                    Text("Working states loop; success, wave and failure are brief. Input reactions stay responsive during status updates.").font(.caption).foregroundStyle(.secondary)
                    if !reactions.error.isEmpty { Text(reactions.error).foregroundStyle(.red) }
                }.padding(8)
            }
        }
    }
}
