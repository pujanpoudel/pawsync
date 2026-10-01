import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum CatalogTransport {
    static func permitted(_ url: URL, zip: Bool = false) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil && url.fragment == nil && url.query == nil &&
        url.host == (zip ? "zip.openpets.dev" : "openpets.dev") && url.path.hasPrefix("/pets/") && !url.path.contains("..")
    }
    static func get(_ url: URL, limit: Int = 3*1024*1024, zip: Bool = false) async throws -> Data {
        guard permitted(url,zip:zip) else { throw PawError.message("This catalog URL is not allowed.") }
        let config=URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest=5; config.timeoutIntervalForResource=zip ? 30 : 8
        config.urlCache=nil; config.httpMaximumConnectionsPerHost=2
        let session=URLSession(configuration:config,delegate:NoRedirects(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let (stream,response)=try await session.bytes(from:url)
        guard let http=response as? HTTPURLResponse,http.statusCode == 200,http.url == url,
              response.expectedContentLength <= Int64(limit) else { throw PawError.message("The pet service returned an invalid response.") }
        var data=Data(); data.reserveCapacity(min(limit,max(0,Int(response.expectedContentLength))))
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < limit else { throw PawError.message("Pet service response exceeded its limit.") }
            data.append(byte)
        }
        return data
    }
}

/// Turn a bounded catalog image into a small, independent PNG. Sprite-sheet
/// previews use the same neutral cell as the native frame renderer.
enum GalleryImageDecoder {
    static func render(_ data:Data, sheet:Bool, rows:Int, detail:Bool) throws -> Data {
        guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? Int,
              let height=properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,height > 0,width <= 2048,height <= 3072,
              (!sheet || (width.isMultiple(of:8) && height.isMultiple(of:rows))) else { throw PawError.message("The gallery preview has invalid dimensions.") }
        let options:[CFString:Any]=[
            kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceShouldCache:false,
            kCGImageSourceThumbnailMaxPixelSize:detail ? 1536 : 640
        ]
        guard let scaled=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else { throw PawError.message("The gallery preview could not be decoded.") }
        let chosen:CGImage
        if sheet {
            let cellWidth=scaled.width/8,cellHeight=scaled.height/rows
            guard cellWidth > 0,cellHeight > 0,
                  let crop=scaled.cropping(to:CGRect(x:(rows == 11 ? 6 : 0)*cellWidth,y:0,width:cellWidth,height:cellHeight)),
                  let context=CGContext(data:nil,width:cellWidth,height:cellHeight,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PawError.message("The gallery sprite sheet has no preview frame.") }
            context.draw(crop,in:CGRect(x:0,y:0,width:cellWidth,height:cellHeight))
            guard let copy=context.makeImage() else { throw PawError.message("The gallery preview could not be copied.") }
            chosen=copy
        } else { chosen=scaled }
        let output=NSMutableData()
        guard let destination=CGImageDestinationCreateWithData(output,UTType.png.identifier as CFString,1,nil) else { throw PawError.message("The gallery preview could not be prepared.") }
        CGImageDestinationAddImage(destination,chosen,nil)
        guard CGImageDestinationFinalize(destination),output.length <= 2*1024*1024 else { throw PawError.message("The gallery preview is too large.") }
        return output as Data
    }
}

struct CatalogPet: Codable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let thumbnail: URL?
    let spritesheet: URL?
    let preview: URL?
    let zip: URL
    let category: String?
    let subcategory: String?
    let featured: Bool?
    let original: Bool?
    let spriteVersionNumber: Int?
    func validate() throws {
        guard id.range(of:"^[a-z0-9][a-z0-9._-]{0,79}$",options:.regularExpression) != nil,!id.contains(".."),
              !displayName.isEmpty,displayName.count <= 120,description.count <= 4000,
              CatalogTransport.permitted(zip,zip:true),zip.path.hasSuffix(".zip"),
              (spriteVersionNumber == nil || spriteVersionNumber == 2),
              [thumbnail,spritesheet,preview].compactMap({$0}).allSatisfy({CatalogTransport.permitted($0)}) else { throw PawError.message("Invalid catalog pet.") }
    }
}

@MainActor final class PetCatalogService: ObservableObject {
    struct Index: Codable { let version:Int; let total:Int; let pages:[URL]; let search:URL? }
    struct Page: Codable { let version:Int; let page:Int?; let pets:[CatalogPet] }
    struct SearchPage: Codable {
        struct Entry: Codable { let id:String; let displayName:String; let searchText:String; let catalogPage:Int; let original:Bool?; let featured:Bool?; let category:String? }
        let version:Int; let pets:[Entry]
    }
    @Published private(set) var pets:[CatalogPet]=[]
    @Published private(set) var installed:[ImportedPet]=PetStore.imports
    @Published private(set) var loading=false
    @Published private(set) var busyID:String?
    @Published private(set) var total=0
    @Published private(set) var message="Gallery downloads are optional. Your installed pets work offline."
    @Published private(set) var thumbnails:[String:NSImage]=[:]
    @Published private(set) var detailImages:[String:NSImage]=[:]
    @Published private(set) var installedThumbnails:[String:NSImage]=[:]
    @Published private(set) var installedDetailImages:[String:NSImage]=[:]
    @Published var enabled=UserDefaults.standard.bool(forKey:"petCatalogEnabled") { didSet { UserDefaults.standard.set(enabled,forKey:"petCatalogEnabled"); if !enabled { generation+=1; task?.cancel(); download?.cancel(); imageTasks.values.forEach{$0.cancel()}; imageTasks.removeAll(); thumbnails.removeAll(); detailImages.removeAll(); imageFailures.removeAll(); loading=false } } }
    var onInstalled: ((String)->Void)?
    var onRemoved: ((String)->Void)?
    private var index:Index?
    private var pages:[Int:Page]=[:]
    private var search:[SearchPage.Entry]=[]
    private var task:Task<Void,Never>?
    private var download:Task<Void,Never>?
    private var imageTasks:[String:Task<Void,Never>]=[:]
    @Published private(set) var imageFailures:Set<String>=[]
    private var thumbnailOrder:[String]=[]
    private var detailOrder:[String]=[]
    private var installedOrder:[String]=[]
    private var installedDetailOrder:[String]=[]
    private var generation=0
    private let cache=PetStore.root.appendingPathComponent("Catalog",isDirectory:true)
    var loadedPages:Int { pages.count }
    var pageCount:Int { index?.pages.count ?? 1 }

    func loadThumbnail(_ pet:CatalogPet) { loadImage(pet,detail:false) }
    func loadPreview(_ pet:CatalogPet) { loadImage(pet,detail:true) }
    func previewFailed(_ pet:CatalogPet)->Bool { imageFailures.contains("detail-\(pet.id)") || (pet.spritesheet ?? pet.preview ?? pet.thumbnail) == nil }
    func loadInstalledThumbnail(_ pet:ImportedPet) { loadInstalledImage(pet,detail:false) }
    func loadInstalledPreview(_ pet:ImportedPet) { loadInstalledImage(pet,detail:true) }
    private func loadInstalledImage(_ pet:ImportedPet,detail:Bool) {
        let key="installed-\(detail ? "detail" : "thumb")-\(pet.id)"
        guard (detail ? installedDetailImages[pet.id] : installedThumbnails[pet.id]) == nil,
              imageTasks[key] == nil,!imageFailures.contains(key) else { return }
        let url=pet.directory.appendingPathComponent("spritesheet.webp")
        imageTasks[key]=Task { [weak self] in
            guard let self else { return }
            defer { self.imageTasks.removeValue(forKey:key) }
            do {
                let png=try await Task.detached(priority:.utility) {
                    let values=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
                    guard values.isRegularFile == true,(values.fileSize ?? Int.max) <= 100*1024*1024 else { throw PawError.message("Invalid installed pet preview.") }
                    return try GalleryImageDecoder.render(Data(contentsOf:url,options:.mappedIfSafe),sheet:true,rows:pet.rows,detail:detail)
                }.value
                guard self.installed.contains(where:{$0.id == pet.id}),let image=NSImage(data:png) else { return }
                if detail {
                    self.installedDetailImages[pet.id]=image; self.installedDetailOrder.removeAll{$0 == pet.id}; self.installedDetailOrder.append(pet.id)
                    if self.installedDetailOrder.count > 6 { self.installedDetailImages.removeValue(forKey:self.installedDetailOrder.removeFirst()) }
                } else {
                    self.installedThumbnails[pet.id]=image; self.installedOrder.removeAll{$0 == pet.id}; self.installedOrder.append(pet.id)
                    if self.installedOrder.count > 36 { self.installedThumbnails.removeValue(forKey:self.installedOrder.removeFirst()) }
                }
            } catch is CancellationError { }
            catch { self.imageFailures.insert(key) }
        }
    }
    private func loadImage(_ pet:CatalogPet,detail:Bool) {
        guard enabled else { return }
        let key="\(detail ? "detail" : "thumb")-\(pet.id)"
        guard imageTasks[key] == nil,!imageFailures.contains(key),
              (detail ? detailImages[pet.id] : thumbnails[pet.id]) == nil else { return }
        guard let url=(detail ? pet.spritesheet ?? pet.preview ?? pet.thumbnail : pet.thumbnail ?? pet.preview ?? pet.spritesheet) else { return }
        let sheet=url == pet.spritesheet || url.lastPathComponent == "spritesheet.webp"
        let rows=pet.spriteVersionNumber == 2 ? 11 : 9
        let current=generation
        imageTasks[key]=Task { [weak self] in
            guard let self else { return }
            defer { self.imageTasks.removeValue(forKey:key) }
            do {
                let data=try await CatalogTransport.get(url,limit:sheet ? 10*1024*1024 : 2*1024*1024)
                let png=try await Task.detached(priority:.utility) { try GalleryImageDecoder.render(data,sheet:sheet,rows:rows,detail:detail) }.value
                guard self.enabled,self.generation == current,let image=NSImage(data:png) else { return }
                if detail {
                    self.detailImages[pet.id]=image; self.detailOrder.removeAll{$0 == pet.id}; self.detailOrder.append(pet.id)
                    if self.detailOrder.count > 6 { self.detailImages.removeValue(forKey:self.detailOrder.removeFirst()) }
                } else {
                    self.thumbnails[pet.id]=image; self.thumbnailOrder.removeAll{$0 == pet.id}; self.thumbnailOrder.append(pet.id)
                    if self.thumbnailOrder.count > 36 { self.thumbnails.removeValue(forKey:self.thumbnailOrder.removeFirst()) }
                }
            } catch is CancellationError { }
            catch { if self.enabled,self.generation == current { self.imageFailures.insert(key) } }
        }
    }

    init() {
        if let data=try? Data(contentsOf:cache.appendingPathComponent("index.json")),let cached=try? JSONDecoder().decode(Index.self,from:data),Self.valid(cached) { index=cached; total=cached.total }
        if let index {
            for i in index.pages.indices {
                if let data=try? Data(contentsOf:cache.appendingPathComponent("page-\(i).json")),let page=try? Self.page(data) { pages[i]=page }
            }
            rebuild()
        }
        if pets.isEmpty,let url=Bundle.main.url(forResource:"CatalogFixture",withExtension:"json"),let data=try? Data(contentsOf:url),let fallback=try? Self.page(data) { pages=[0:fallback]; total=fallback.pets.count; rebuild() }
    }
    private static func valid(_ index:Index) -> Bool {
        index.version == 3 && (1...100000).contains(index.total) && (1...200).contains(index.pages.count) && index.pages.allSatisfy({CatalogTransport.permitted($0)}) && index.search.map({CatalogTransport.permitted($0)}) != false
    }
    private static func page(_ data:Data) throws -> Page {
        let value=try JSONDecoder().decode(Page.self,from:data)
        guard [2,3].contains(value.version),value.pets.count <= 10000,Set(value.pets.map(\.id)).count == value.pets.count else { throw PawError.message("Invalid catalog page.") }
        for pet in value.pets { try pet.validate(); if value.version == 3,!(["western","asian"].contains(pet.category ?? "")) { throw PawError.message("Invalid pet category.") } }
        return value
    }
    private func cache(_ data:Data,name:String) {
        try? FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
        try? data.write(to:cache.appendingPathComponent(name),options:.atomic)
    }
    private func rebuild() {
        var unique:[String:CatalogPet]=[:]
        for page in pages.sorted(by:{$0.key < $1.key}).map(\.value) { for pet in page.pets { unique[pet.id]=pet } }
        pets=unique.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    func refresh() {
        guard enabled,!loading else { return }
        generation+=1; let current=generation; loading=true; task?.cancel(); imageTasks.values.forEach{$0.cancel()}; imageTasks.removeAll(); imageFailures.removeAll()
        task=Task { [weak self] in
            guard let self else { return }
            defer { if current == self.generation { self.loading=false } }
            do {
                let data=try await CatalogTransport.get(URL(string:"https://openpets.dev/pets/catalog.v3.json")!)
                let index=try JSONDecoder().decode(Index.self,from:data)
                guard Self.valid(index) else { throw PawError.message("Unsupported pet catalog.") }
                guard current == self.generation,self.enabled else { return }
                self.index=index; self.total=index.total; self.pages=[:]; self.search=[]; self.cache(data,name:"index.json")
                try await self.loadPage(0,generation:current)
                self.message="Gallery ready. Showing original and featured pets; an exact ID can find any catalog pet."
            } catch is CancellationError { }
            catch {
                guard current == self.generation,self.enabled else { return }
                do {
                    let data=try await CatalogTransport.get(URL(string:"https://openpets.dev/pets/catalog.v2.json")!)
                    let fallback=try Self.page(data)
                    guard current == self.generation,self.enabled else { return }
                    self.index=nil; self.pages=[0:fallback]; self.total=fallback.pets.count; self.rebuild(); self.cache(data,name:"fallback.json")
                    self.message="Using the compatible gallery while v3 is unavailable."
                } catch {
                    guard current == self.generation,self.enabled else { return }
                    if let data=try? Data(contentsOf:self.cache.appendingPathComponent("fallback.json")),let fallback=try? Self.page(data) { self.pages=[0:fallback]; self.rebuild() }
                    self.message=self.pets.isEmpty ? "Gallery unavailable. Installed pets and local imports still work. Try Refresh." : "Offline gallery cache. Refresh when you're connected."
                }
            }
        }
    }
    private func loadPage(_ number:Int,generation:Int) async throws {
        guard let index,index.pages.indices.contains(number),pages[number] == nil else { return }
        let data=try await CatalogTransport.get(index.pages[number]); let page=try Self.page(data)
        guard generation == self.generation,enabled else { throw CancellationError() }
        guard page.version == 3,page.page == number else { throw PawError.message("Catalog page identity mismatch.") }
        pages[number]=page; cache(data,name:"page-\(number).json"); rebuild()
    }
    func loadMore() {
        guard enabled,!loading,let index,let next=index.pages.indices.first(where:{pages[$0] == nil}) else { return }
        let current=generation; loading=true
        task=Task { defer { if current == generation { loading=false } }; do { try await loadPage(next,generation:current) } catch is CancellationError {} catch { if current == generation { message=error.localizedDescription } } }
    }
    func searchFor(_ query:String) {
        guard enabled,!query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,!loading else { return }
        let query=query.lowercased().trimmingCharacters(in:.whitespacesAndNewlines); let current=generation; loading=true
        task=Task {
            defer { if current == generation { loading=false } }
            do {
                if search.isEmpty,let url=index?.search {
                    let data=try await CatalogTransport.get(url); let lookup=try JSONDecoder().decode(Index.self,from:data)
                    guard Self.valid(lookup) else { throw PawError.message("Invalid search index.") }
                    var entries:[SearchPage.Entry]=[]
                    for url in lookup.pages {
                        let data=try await CatalogTransport.get(url); let page=try JSONDecoder().decode(SearchPage.self,from:data)
                        guard page.version == 3,page.pets.count <= 500,page.pets.allSatisfy({$0.id.count <= 80 && $0.displayName.count <= 120 && $0.searchText.count <= 4000 && (index?.pages.indices.contains($0.catalogPage) ?? false)}) else { throw PawError.message("Invalid search page.") }
                        guard current == generation,enabled else { throw CancellationError() }; entries.append(contentsOf:page.pets)
                    }
                    search=entries
                }
                let matches=search.filter { $0.id == query || ($0.original == true || $0.featured == true) && ($0.displayName.lowercased().contains(query) || $0.searchText.lowercased().contains(query)) }
                for page in Set(matches.map(\.catalogPage)).sorted() { try await loadPage(page,generation:current) }
                message=matches.isEmpty ? "No matching gallery pets. You can also import a ZIP or folder." : "Search results loaded."
            } catch is CancellationError {} catch { message=error.localizedDescription }
        }
    }
    func install(_ pet:CatalogPet) {
        guard enabled,busyID == nil else { return }
        busyID=pet.id
        download=Task {
            defer { busyID=nil }
            do {
                try pet.validate(); let data=try await CatalogTransport.get(pet.zip,limit:50*1024*1024,zip:true)
                try Task.checkCancellation(); guard enabled else { throw CancellationError() }
                let id=try await Task.detached(priority:.userInitiated) { try PetInstallation.install(SafeArchive.unpack(data),expectedID:pet.id,origin:"catalog",source:pet.zip.absoluteString) }.value
                reloadInstalled(); message="\(pet.displayName) joined your companions."; onInstalled?(id)
            } catch is CancellationError { message="Download canceled." } catch { message=error.localizedDescription }
        }
    }
    func chooseImport() {
        let panel=NSOpenPanel(); panel.canChooseDirectories=true; panel.canChooseFiles=true; panel.allowsMultipleSelection=false
        panel.title="Import an OpenPets pet"; panel.message="Choose a pet ZIP, or a folder containing pet.json and spritesheet.webp."
        guard panel.runModal() == .OK,let url=panel.url else { return }
        importLocal(url)
    }
    func importLocal(_ url:URL) {
        guard busyID == nil else { return }; busyID="local-import"
        Task {
            defer { busyID=nil }
            let granted=url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
            do { let id=try await Task.detached { try PetInstallation.install(PetInstallation.localFiles(url)) }.value; reloadInstalled(); message="Your pet is installed."; onInstalled?(id) }
            catch { message=error.localizedDescription }
        }
    }
    func importCodexPets() {
        let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/pets")
        let candidates=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey])) ?? []
        guard busyID == nil else { return }; busyID="codex-import"
        Task {
            defer { busyID=nil }; var imported=0,failed=0
            for url in candidates.prefix(200) {
                do { _=try await Task.detached { try PetInstallation.install(PetInstallation.localFiles(url),origin:"codex") }.value; imported+=1 } catch { failed+=1 }
            }
            reloadInstalled(); message="Imported \(imported) Codex pets; skipped \(failed) invalid entries. Source files were unchanged."
        }
    }
    func remove(_ pet:ImportedPet) {
        do { try PetInstallation.remove(pet); reloadInstalled(); onRemoved?(pet.id); message="\(pet.name) moved to Trash." } catch { message=error.localizedDescription }
    }
    func reloadInstalled() { PetStore.invalidateImports(); installed=PetStore.imports; let ids=Set(installed.map(\.id)); installedThumbnails=installedThumbnails.filter{ids.contains($0.key)}; installedDetailImages=installedDetailImages.filter{ids.contains($0.key)}; installedOrder.removeAll{!ids.contains($0)}; installedDetailOrder.removeAll{!ids.contains($0)} }
    func stop() { generation+=1; task?.cancel(); download?.cancel(); imageTasks.values.forEach{$0.cancel()}; imageTasks.removeAll() }
}
