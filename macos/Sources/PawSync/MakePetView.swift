import SwiftUI
import AppKit
import SpriteKit
import UniformTypeIdentifiers

private typealias MakerState<V> = SwiftUI.State<V>
struct MakePetView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var creator:PhotoPetCreator
    @ObservedObject var custom:CustomPetService
    @MakerState private var provider:PetImageProvider = .gemini
    @MakerState private var key=""
    @MakerState private var savedKey=false
    @MakerState private var name=""
    @MakerState private var dropTarget=false
    @MakerState private var localError=""
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(alignment:.top,spacing:22) {
                Image(systemName:"heart.circle.fill").font(.system(size:48)).foregroundStyle(LibraryStyle.pink)
                VStack(alignment:.leading,spacing:7) {
                    Text("Your real pet, a little desk buddy").font(.system(size:21,weight:.bold,design:.rounded))
                    Text("Choose a photo, connect your image provider, then preview your new friend before adding them.").font(.callout).foregroundStyle(LibraryStyle.muted)
                }
            }
            VStack(alignment:.leading,spacing:16) {
                Label("1 · Choose a pet photo",systemImage:"photo").font(.headline)
                Button {custom.choosePhoto()} label: {
                    VStack(spacing:10) {
                        if let image=custom.preview {Image(nsImage:image).resizable().scaledToFit().frame(height:140).clipShape(RoundedRectangle(cornerRadius:18))}
                        else {Image(systemName:"photo.badge.plus").font(.system(size:34)).foregroundStyle(LibraryStyle.purple)}
                        Text(custom.selectedURL?.lastPathComponent ?? "Drop a photo here or choose a file").font(.system(size:14,weight:.semibold,design:.rounded))
                        Text("JPEG, PNG or HEIC · up to 15 MB").font(.caption).foregroundStyle(LibraryStyle.muted)
                    }.padding(25).frame(maxWidth:.infinity).background(LibraryStyle.purple.opacity(dropTarget ? 0.13:0.04),in:RoundedRectangle(cornerRadius:24)).contentShape(RoundedRectangle(cornerRadius:24))
                }.buttonStyle(.plain).disabled(creator.busy || custom.busy)
                .onDrop(of:[.fileURL],isTargeted:$dropTarget) {providers in
                    guard !creator.busy,!custom.busy,let item=providers.first else{return false}
                    _=item.loadObject(ofClass:URL.self){url,_ in if let url{DispatchQueue.main.async{custom.select(url)}}};return true
                }
                TextField("Your pet’s name",text:$name).textFieldStyle(.roundedBorder)
                if let error=custom.error {Text(error).font(.caption).foregroundStyle(.red)}
            }.padding(22).background(LibraryStyle.paper,in:RoundedRectangle(cornerRadius:26))
            VStack(alignment:.leading,spacing:15) {
                Label("2 · Connect your image provider",systemImage:"sparkles").font(.headline)
                Picker("Provider",selection:$provider) {ForEach(PetImageProvider.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented).disabled(creator.busy)
                if savedKey {
                    HStack {Label("Key saved securely in Keychain",systemImage:"lock.fill").font(.caption).foregroundStyle(LibraryStyle.purple);Spacer();Button("Remove key"){KeychainStore.delete(provider.keyName);savedKey=false}.buttonStyle(CozyButton())}.disabled(creator.busy)
                } else {
                    HStack {SecureField("\(provider.rawValue) API key",text:$key).textFieldStyle(.roundedBorder);Button("Save key"){if creator.saveKey(key,provider:provider){key="";savedKey=true}}.buttonStyle(CozyButton()).disabled(key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}.disabled(creator.busy)
                }
                HStack {Button("Get a \(provider.rawValue) key"){NSWorkspace.shared.open(provider.keyURL)}.buttonStyle(.link);Spacer();Text(provider.model).font(.caption2).foregroundStyle(LibraryStyle.muted)}
                Text("When you click Create, your photo goes directly to \(provider.rawValue). One image edit is billed by that provider; no PawSync credits are used. Your key stays on this Mac.").font(.caption).foregroundStyle(LibraryStyle.muted)
            }.padding(22).background(LibraryStyle.paper,in:RoundedRectangle(cornerRadius:26))
            if !localError.isEmpty {Text(localError).foregroundStyle(.red).font(.callout)}
            if !creator.error.isEmpty {Text(creator.error).foregroundStyle(.red).font(.callout)}
            if creator.busy {
                HStack {ProgressView().controlSize(.small);Text(creator.status).font(.callout);Spacer();Button("Cancel"){creator.cancel()}.buttonStyle(CozyButton())}
            } else if let draft=creator.draft {
                VStack(spacing:15) {
                    Text("Meet \(draft.manifest.name)").font(.system(size:22,weight:.bold,design:.rounded))
                    DraftPetPreview(draft:draft).frame(width:280,height:260)
                    Text("Check the face and how the pieces fit before adding your friend.").font(.caption).foregroundStyle(LibraryStyle.muted)
                    HStack {Button("Add to my desktop"){creator.install()}.buttonStyle(CozyButton(prominent:true));Button("Discard & try again"){creator.discard()}.buttonStyle(CozyButton())}
                }.frame(maxWidth:.infinity).padding(22).background(LibraryStyle.paper,in:RoundedRectangle(cornerRadius:26))
            } else {
                Button(creator.error.isEmpty ? "Create my little friend":"Retry with this photo") {
                    guard let url=custom.selectedURL else{return}
                    do {let photo=try custom.validate(url);localError="";creator.generate(provider:provider,photo:photo,name:name)}
                    catch {localError=error.localizedDescription}
                }.buttonStyle(CozyButton(prominent:true)).disabled(custom.selectedURL == nil || !savedKey || custom.busy)
            }
        }.onAppear{savedKey=KeychainStore.read(provider.keyName) != nil}
        .onChange(of:provider){_,_ in key="";savedKey=KeychainStore.read(provider.keyName) != nil;localError=""}
    }
}
private struct DraftPetPreview:NSViewRepresentable {
    let draft:PhotoPetDraft
    func makeNSView(context:Context)->SKView {
        let view=SKView();view.allowsTransparency=true;view.preferredFramesPerSecond=30
        let scene=SKScene(size:CGSize(width:280,height:260));scene.backgroundColor = .clear;scene.scaleMode = .aspectFit
        if let pet=try? PetSpriteNode(manifest:draft.manifest,directory:draft.directory){pet.position=CGPoint(x:140,y:32);scene.addChild(pet)}
        view.presentScene(scene);DispatchQueue.main.asyncAfter(deadline:.now()+0.2){[weak view] in view?.isPaused=true};return view
    }
    func updateNSView(_ nsView:SKView,context:Context){}
}
