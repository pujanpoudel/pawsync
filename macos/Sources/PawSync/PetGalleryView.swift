import SwiftUI
import AppKit

private typealias GalleryState<Value> = SwiftUI.State<Value>
private enum GalleryPreview:Identifiable {
    case installed(ImportedPet),catalog(CatalogPet)
    var id:String { switch self { case .installed(let pet):return "installed-\(pet.id)"; case .catalog(let pet):return "catalog-\(pet.id)" } }
}

struct PetGalleryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: PetCatalogService
    @ObservedObject var preferences: Preferences
    @GalleryState private var query = ""
    @GalleryState private var category = "all"
    @GalleryState private var originals = false
    @GalleryState private var featured = false
    @GalleryState private var preview: GalleryPreview?
    private var results: [CatalogPet] {
        let text=query.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        return catalog.pets.filter { pet in
            (category == "all" || pet.category == category) && (!originals || pet.original == true) && (!featured || pet.featured == true) &&
            (text.isEmpty ? (pet.original == true || pet.featured == true || pet.category == nil) : pet.id == text || (pet.original == true || pet.featured == true || pet.category == nil) && (pet.displayName.lowercased().contains(text) || pet.description.lowercased().contains(text)))
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            GroupBox("OpenPets companions") {
                LazyVStack(alignment:.leading,spacing:12) {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:140),spacing:12)],spacing:12) {
                        ForEach(catalog.installed) { pet in
                            VStack(spacing:9) {
                                Button { preview = .installed(pet) } label: {
                                    VStack(spacing:8) {
                                        if let image=catalog.installedThumbnails[pet.id] {
                                            Image(nsImage:image).resizable().scaledToFit().frame(height:100)
                                        } else { Image(systemName:"pawprint.fill").font(.title2).foregroundStyle(.purple).frame(height:100) }
                                        Text(pet.name).font(.system(size:13,weight:.semibold)).lineLimit(1)
                                    }.frame(maxWidth:.infinity).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("Preview \(pet.name)")
                                Button(preferences.companion == pet.id ? "Selected" : "Use pet") { preferences.companion=pet.id }.disabled(preferences.companion == pet.id)
                            }.padding(12).background(Color.purple.opacity(preferences.companion == pet.id ? 0.10 : 0.035),in:RoundedRectangle(cornerRadius:12))
                                .onAppear { catalog.loadInstalledThumbnail(pet) }
                        }
                    }
                    DisclosureGroup("Import your own pets") {
                        HStack { Button("ZIP or folder…") { catalog.chooseImport() }; Button("From Codex") { catalog.importCodexPets() } }.disabled(catalog.busyID != nil)
                        Text("Imported pets stay on this Mac. Original files are kept.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(8)
            }
            GroupBox("OpenPets gallery") {
                VStack(alignment:.leading,spacing:12) {
                    Toggle("Allow optional gallery downloads",isOn:$catalog.enabled).onChange(of:catalog.enabled) { _,enabled in if enabled { catalog.refresh() } }
                    Text("Browse community pets from OpenPets. Your typing, photos and account details stay private.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Search name or exact pet ID",text:$query).onSubmit { catalog.searchFor(query) }
                        Button("Search") { catalog.searchFor(query) }.disabled(!catalog.enabled || catalog.loading)
                        Button("Refresh") { catalog.refresh() }.disabled(!catalog.enabled || catalog.loading)
                    }
                    DisclosureGroup("Filter pets") { HStack {
                        Picker("Category",selection:$category) { Text("All").tag("all"); Text("Western").tag("western"); Text("Asian").tag("asian") }.frame(width:180)
                        Toggle("Originals",isOn:$originals); Toggle("Featured",isOn:$featured)
                    } }
                    Text(catalog.message).font(.callout).foregroundStyle(.secondary).accessibilityLabel(catalog.message)
                    if catalog.loading || catalog.busyID != nil { ProgressView().controlSize(.small) }
                    Text("\(results.count) matching loaded pets · \(catalog.total) in catalog").font(.caption).foregroundStyle(.secondary)
                    LazyVStack(alignment:.leading,spacing:14) {
                        ForEach(results) { pet in
                            HStack(alignment:.top) {
                                Button { preview = .catalog(pet) } label: {
                                    if let image=catalog.thumbnails[pet.id] {
                                        Image(nsImage:image).resizable().scaledToFit().frame(width:70,height:76)
                                    } else { Image(systemName:"pawprint.fill").font(.title2).foregroundStyle(.purple.opacity(0.6)).frame(width:70,height:76) }
                                }.buttonStyle(.plain).accessibilityLabel("Preview \(pet.displayName)")
                                VStack(alignment:.leading,spacing:5) {
                                    Text(pet.displayName).font(.headline)
                                    Text(pet.description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                    Text("\(pet.id) · \(pet.subcategory ?? pet.category ?? "Community")\(pet.original == true ? " · Original" : "")").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer()
                                Button("Preview") { preview = .catalog(pet) }
                                Button(catalog.installed.contains(where:{$0.folder == pet.id}) ? "Reinstall" : "Install") { catalog.install(pet) }.disabled(!catalog.enabled || catalog.busyID != nil)
                            }.onAppear { catalog.loadThumbnail(pet) }
                            Divider()
                        }
                    }
                    if catalog.loadedPages < catalog.pageCount { Button("Load more pets") { catalog.loadMore() }.disabled(!catalog.enabled || catalog.loading) }
                    Text("Catalog art has individual provenance. User installation does not grant redistribution rights.").font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
        }.sheet(item:$preview) { item in previewContent(item) }
    }
    @ViewBuilder private func previewContent(_ item:GalleryPreview) -> some View {
        switch item {
        case .installed(let pet):
            VStack(alignment:.leading,spacing:14) {
                Text(pet.name).font(.title2.bold())
                Group {
                    if let image=catalog.installedDetailImages[pet.id] ?? catalog.installedThumbnails[pet.id] { Image(nsImage:image).resizable().scaledToFit() }
                    else if catalog.imageFailures.contains("installed-detail-\(pet.id)") { Label("Preview unavailable",systemImage:"pawprint.fill").foregroundStyle(.secondary) }
                    else { ProgressView("Loading pet preview…") }
                }.frame(maxWidth:.infinity).frame(height:218)
                Text("By \(pet.author)").foregroundStyle(.secondary)
                Text(pet.source).font(.caption).textSelection(.enabled)
                HStack { Button("Use & wave") { preferences.companion=pet.id; model.overlay.wave() }; Button("Preview jump") { preferences.companion=pet.id; model.overlay.celebrate() }; Spacer(); Button("Done") { preview=nil } }
                if pet.local == true { Button("Remove from my pets") { catalog.remove(pet); preview=nil }.font(.caption).help("Move this imported companion to the system Trash") }
            }.padding(24).frame(width:470).onAppear { catalog.loadInstalledPreview(pet) }
        case .catalog(let pet):
            VStack(alignment:.leading,spacing:14) {
                Text(pet.displayName).font(.title2.bold())
                Group {
                    if let image=catalog.detailImages[pet.id] ?? catalog.thumbnails[pet.id] {
                        Image(nsImage:image).resizable().scaledToFit()
                    } else if catalog.enabled && !catalog.previewFailed(pet) { ProgressView("Loading pet preview…") }
                    else if catalog.enabled { Label("Preview unavailable",systemImage:"pawprint.fill").foregroundStyle(.secondary) }
                    else { Label("Enable gallery downloads to see this pet",systemImage:"pawprint.fill").foregroundStyle(.secondary) }
                }.frame(maxWidth:.infinity).frame(height:218)
                Text(pet.description).font(.callout)
                Text("\(pet.id) · \(pet.subcategory ?? pet.category ?? "Community")").font(.caption).foregroundStyle(.secondary)
                HStack {
                    if let installed=catalog.installed.first(where:{$0.folder == pet.id}) {
                        Button("Use pet") { preferences.companion=installed.id; preview=nil }
                    } else { Button("Install pet") { catalog.install(pet); preview=nil }.disabled(!catalog.enabled || catalog.busyID != nil) }
                    Spacer(); Button("Done") { preview=nil }
                }
            }.padding(24).frame(width:470).onAppear { catalog.loadPreview(pet) }
        }
    }
}
