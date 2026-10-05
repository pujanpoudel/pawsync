import Foundation
import Combine
import CryptoKit

@MainActor enum LibraryContent {
    struct Pet:Codable {var id:String;var sha256:String;var requiresSKU:String?;var collection:String?;var unlockLevel:Int?}
    struct Collection:Codable,Identifiable {var id:String;var name:String;var sku:String;var priceLabel:String?}
    struct Catalog:Codable {var version:Int;var items:[FreeHat];var lines:[String];var pets:[Pet]?=nil;var collections:[Collection]?=nil}
    private(set) static var pets:[Pet]=[]
    private(set) static var collections:[Collection]=[]
    private(set) static var lines:[String]=[]
    static func load() {
        let bundled=Bundle.main.url(forResource:"catalog",withExtension:"json",subdirectory:"Library")
        let cached=PetStore.root.appendingPathComponent("Library/content.json")
        for url in [bundled,cached] {
            guard let url,let data=try? Data(contentsOf:url),data.count<=1_048_576,let catalog=try? JSONDecoder().decode(Catalog.self,from:data) else{continue}
            try? apply(catalog)
        }
    }
    static func apply(_ catalog:Catalog) throws {
        guard catalog.version==1,catalog.lines.count<=200,catalog.lines.allSatisfy({!$0.isEmpty && $0.count<=300}) else{throw PawError.message("Invalid companion cheers.")}
        let pets=catalog.pets ?? [],collections=catalog.collections ?? []
        guard pets.count<=100,collections.count<=10,pets.allSatisfy({p in p.id.range(of:"^[a-z0-9][a-z0-9_-]{0,79}$",options:.regularExpression) != nil && p.sha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil && p.requiresSKU.map{$0.hasPrefix("collection.") || $0.hasPrefix("accessory.pack.")} != false && (1...1000).contains(p.unlockLevel ?? 1)}),collections.allSatisfy({c in c.id.hasPrefix("collection.") && c.id.count<=80 && c.name.count<=80 && c.sku.hasPrefix("collection.")}) else{throw PawError.message("Invalid collection metadata.")}
        try FreeHat.installContent(catalog.items);lines=catalog.lines;self.pets=pets;self.collections=collections
    }
}
@MainActor final class LibraryContentService:ObservableObject {
    @Published var enabled:Bool {didSet{UserDefaults.standard.set(enabled,forKey:"library.contentEnabled");if enabled{Task{await refresh()}}}}
    @Published private(set) var status="Bundled items and cheers are ready offline."
    @Published private(set) var busy=false
    var ownedSKUs:(()->[String])?
    var onInstalled:(()->Void)?
    private let api:APIClient
    init(api:APIClient){self.api=api;enabled=UserDefaults.standard.bool(forKey:"library.contentEnabled");LibraryContent.load()}
    func refresh() async {
        guard enabled,!busy else{return};busy=true;defer{busy=false}
        do{
            let data=try await api.request("v1/library/catalog",authenticated:false)
            guard data.count<=1_048_576 else{throw PawError.message("Library content is too large.")}
            let catalog=try JSONDecoder().decode(LibraryContent.Catalog.self,from:data);try LibraryContent.apply(catalog)
            try LocalState.write(catalog,at:PetStore.root.appendingPathComponent("Library/content.json"))
            let versionURL=PetStore.root.appendingPathComponent("Library/pet-versions.json")
            var versions=(try? JSONDecoder().decode([String:String].self,from:Data(contentsOf:versionURL))) ?? [:]
            for pet in catalog.pets ?? [] {
                guard pet.requiresSKU==nil || ownedSKUs?().contains(pet.requiresSKU!)==true,versions[pet.id] != pet.sha256 else{continue}
                let zip=try await api.request("v1/library/pets/"+pet.id,authenticated:pet.requiresSKU != nil)
                guard zip.count<=10*1024*1024,SHA256.hash(data:zip).map({String(format:"%02x",$0)}).joined()==pet.sha256 else{throw PawError.message("Pet download failed its integrity check.")}
                _=try PetInstallation.install(SafeArchive.unpack(zip),expectedID:pet.id,origin:"catalog",source:"PawSync content service")
                versions[pet.id]=pet.sha256;try LocalState.write(versions,at:versionURL)
            }
            onInstalled?();status="New items, companions and cheers are ready."
        }catch{status="Could not refresh content. Your saved collection is ready offline."}
    }
}
