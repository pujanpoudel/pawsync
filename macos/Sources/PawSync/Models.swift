import AppKit
import Combine
import CryptoKit

enum ScreenAnchor: String, Codable, CaseIterable, Identifiable {
    case dock = "Bottom Dock", activeWindow = "Active Window", notch = "Notch", free = "Free Floating"
    var id: String { rawValue }
}
enum MovementMode: String, Codable, CaseIterable, Identifiable {
    case stay = "Stay put", roam = "Roam around", follow = "Follow the pointer", patrol = "Patrol the screen"
    var id: String { rawValue }
}

struct PetPart: Codable {
    let file: String?
    let pngBase64: String?
    let anchor: [Double]
    let parentOffset: [Double]?
    let textureRect: [Double]?
    let displaySize: [Double]?
    let eyes: [[Double]]?
    enum CodingKeys: String, CodingKey {
        case file, anchor, eyes
        case pngBase64 = "png_base64", parentOffset = "parent_offset"
        case textureRect = "texture_rect", displaySize = "display_size"
    }
}

struct PetManifest: Codable {
    let id: String
    let name: String
    let parts: [String: PetPart]
    let previewRect: [Double]?
    enum CodingKeys: String, CodingKey { case id, name, parts; case previewRect = "preview_rect" }
    static let required = ["body", "head", "left_paw", "right_paw", "tail"]
    func validate() throws {
        guard UUID(uuidString: id) != nil || PetStore.builtInIDs.contains(id) else { throw PawError.message("Invalid pet identifier.") }
        for key in Self.required {
            guard let part = parts[key], part.anchor.count == 2,
                  part.anchor.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  part.parentOffset?.count ?? 2 == 2,
                  (part.parentOffset ?? [0, 0]).allSatisfy({ $0.isFinite && abs($0) < 1024 }) else {
                throw PawError.message("The pet atlas has an invalid \(key) joint.")
            }
            if let file = part.file, file != "\(key).png" && !(PetStore.builtInIDs.contains(id) && file == "illustration.png") { throw PawError.message("Unsafe part filename.") }
            if let rect = part.textureRect {
                guard PetStore.builtInIDs.contains(id), rect.count == 4, rect.allSatisfy({ $0.isFinite && $0 >= 0 }), rect[2] > 0, rect[3] > 0 else { throw PawError.message("Invalid texture region.") }
            }
            if let size = part.displaySize {
                guard size.count == 2, size.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 512 }) else { throw PawError.message("Invalid display size.") }
            }
            if let eyes = part.eyes {
                guard eyes.count == 2, eyes.allSatisfy({ $0.count == 2 && $0.allSatisfy({ $0.isFinite && (0...1).contains($0) }) }) else { throw PawError.message("Invalid eye positions.") }
            }
        }
    }
}

struct AppConfiguration: Codable {
    let apiBaseURL: URL
    let licensePublicKey: String
    let checkoutURLs: [String: URL]
    let sentryDSN: String
    let environment: String
    static func load() -> Self {
        let resources = Bundle.main.resourceURL!
        let local = resources.appendingPathComponent("Config.local.json")
        let url = FileManager.default.fileExists(atPath: local.path) ? local : resources.appendingPathComponent("Config.json")
        do {
            let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            guard value.apiBaseURL.scheme == "https" ||
                    (value.environment == "development" && value.apiBaseURL.host == "127.0.0.1") else { throw PawError.message("API must use HTTPS.") }
            return value
        } catch { fatalError("Invalid bundled PawSync configuration: \(error.localizedDescription)") }
    }
}

enum PawError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum PetStore {
    private static let registryLock=NSLock()
    private static var cachedImports:[ImportedPet]?
    private static let previews:NSCache<NSString,NSImage> = { let cache=NSCache<NSString,NSImage>(); cache.countLimit=24; cache.totalCostLimit=8*1024*1024; return cache }()
    static func invalidateImports() { registryLock.lock(); cachedImports=nil; registryLock.unlock(); previews.removeAllObjects() }
    static let rigIDs = ["pixel-cat", "shibe", "fox", "bunny", "bear", "panda", "hamster", "otter", "capybara"]
    static let rigNames = ["pixel-cat": "Maple the Cat", "shibe": "Mochi the Shibe", "fox": "Ember the Fox", "bunny": "Clover the Bunny", "bear": "Cocoa the Bear", "panda": "Bao the Panda", "hamster": "Peaches the Hamster", "otter": "Pebble the Otter", "capybara": "Pudding the Capybara"]
    static func frameOriginal(_ id:String)->ImportedPet? {
        guard rigIDs.contains(id), Bundle.main.url(forResource:"spritesheet",withExtension:"webp",subdirectory:"OpenPets/originals/\(id)") != nil else { return nil }
        return ImportedPet(id:id,name:rigNames[id] ?? id,folder:"originals/\(id)",columns:8,rows:9,source:"PawSync",author:"PawSync")
    }
    static var imports: [ImportedPet] {
        registryLock.lock(); defer { registryLock.unlock() }
        if let cachedImports { return cachedImports }
        let bundled: [ImportedPet]
        if let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "OpenPets"), let data = try? Data(contentsOf: url) {
            bundled = (try? JSONDecoder().decode([ImportedPet].self, from: data)) ?? []
        } else { bundled = [] }
        let result=bundled + PetInstallation.installed(); cachedImports=result; return result
    }
    static var builtInIDs: [String] { rigIDs + imports.map(\.id) }
    static var builtInNames: [String: String] { rigNames.merging(Dictionary(uniqueKeysWithValues: imports.map { ($0.id, $0.name) })) { _, new in new } }
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PawSync", isDirectory: true)
    }
    static var pets: URL { root.appendingPathComponent("Pets", isDirectory: true) }
    static func directory(for id: String) -> URL {
        if builtInIDs.contains(id) { return Bundle.main.resourceURL!.appendingPathComponent("Pets/\(id)") }
        return pets.appendingPathComponent(id)
    }
    static func load(_ id: String) throws -> PetManifest {
        guard builtInIDs.contains(id) || UUID(uuidString: id) != nil else { throw PawError.message("Invalid pet ID.") }
        let value = try JSONDecoder().decode(PetManifest.self, from: Data(contentsOf: directory(for: id).appendingPathComponent("atlas.json")))
        try value.validate()
        return value
    }
    static func customPets() -> [PetManifest] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: pets, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { try? load($0.lastPathComponent) }.sorted { $0.name < $1.name }
    }
    static func preview(_ id: String) -> NSImage? {
        if let cached=previews.object(forKey:id as NSString) { return cached }
        if let spec=frameOriginal(id) ?? imports.first(where:{$0.id == id}),let data=try? Data(contentsOf:spec.directory.appendingPathComponent("spritesheet.webp"),options:.mappedIfSafe),let png=try? GalleryImageDecoder.render(data,sheet:true,rows:spec.rows,detail:true),let image=NSImage(data:png) {
            previews.setObject(image,forKey:id as NSString,cost:192*208*4); return image
        }
        guard let manifest = try? load(id), let rect = manifest.previewRect, rect.count == 4,
              let image = NSImage(contentsOf: directory(for: id).appendingPathComponent("illustration.png")),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cutout = cg.cropping(to: CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])) else { return nil }
        let scale=min(1,256/Double(max(cutout.width,cutout.height)))
        let width=max(1,Int(Double(cutout.width)*scale)),height=max(1,Int(Double(cutout.height)*scale))
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cutout,in:CGRect(x:0,y:0,width:width,height:height))
        guard let compact=context.makeImage() else { return nil }
        let preview=NSImage(cgImage:compact,size:CGSize(width:width,height:height)); previews.setObject(preview,forKey:id as NSString,cost:width*height*4); return preview
    }
}

@MainActor final class Preferences: ObservableObject {
    // Standard defaults are scoped to this application's bundle identifier.
    // Passing that same identifier to init(suiteName:) is invalid on macOS.
    private let defaults = UserDefaults.standard
    @Published var companion: String { didSet { defaults.set(companion, forKey: "companion") } }
    @Published var anchor: ScreenAnchor { didSet { defaults.set(anchor.rawValue, forKey: "anchor") } }
    @Published var muted: Bool { didSet { defaults.set(muted, forKey: "muted") } }
    @Published var hidden: Bool { didSet { defaults.set(hidden, forKey: "hidden") } }
    @Published var integrations: Bool { didSet { defaults.set(integrations, forKey: "integrations") } }
    @Published var telemetry: Bool { didSet { defaults.set(telemetry, forKey: "telemetry") } }
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var breakMinutes: Int { didSet { defaults.set(breakMinutes, forKey: "breakMinutes") } }
    @Published var accessory: String { didSet { defaults.set(accessory, forKey: "accessory") } }
    @Published var headAccessoriesVisible: Bool { didSet { defaults.set(headAccessoriesVisible, forKey: "headAccessoriesVisible") } }
    @Published var petScale: Double { didSet { defaults.set(petScale, forKey: "petScale") } }
    @Published var dailyGoal: Int { didSet { defaults.set(dailyGoal, forKey: "dailyGoal") } }
    @Published var nickname: String { didSet { defaults.set(nickname, forKey: "nickname") } }
    @Published var reactionsPaused: Bool { didSet { defaults.set(reactionsPaused, forKey: "reactionsPaused") } }
    @Published var movement: MovementMode { didSet { defaults.set(movement.rawValue, forKey: "movement") } }
    @Published var greetings: Bool { didSet { defaults.set(greetings, forKey: "greetings") } }
    @Published var userName: String { didSet { defaults.set(userName, forKey: "userName") } }
    @Published var edgeTraversal: Bool { didSet { defaults.set(edgeTraversal, forKey: "edgeTraversal") } }
    @Published var musicReactive: Bool { didSet { defaults.set(musicReactive, forKey: "musicReactive") } }
    @Published var musicLite: Bool { didSet { defaults.set(musicLite, forKey: "musicLite") } }
    @Published var petOpacity:Double {didSet{defaults.set(petOpacity,forKey:"petOpacity")}}
    @Published var clickThrough:Bool {didSet{defaults.set(clickThrough,forKey:"clickThrough")}}
    @Published var mirrorDock:Bool {didSet{defaults.set(mirrorDock,forKey:"mirrorDock")}}
    var onboarded: Bool { get { defaults.bool(forKey: "onboarded") } set { defaults.set(newValue, forKey: "onboarded") } }
    init() {
        companion = defaults.string(forKey: "companion") ?? "knight-cat"
        anchor = ScreenAnchor(rawValue: defaults.string(forKey: "anchor") ?? "") ?? .dock
        muted = defaults.object(forKey: "muted") as? Bool ?? true
        hidden = defaults.bool(forKey: "hidden")
        integrations = defaults.bool(forKey: "integrations")
        telemetry = defaults.bool(forKey: "telemetry")
        focusMinutes = min(120, max(1, defaults.object(forKey: "focusMinutes") as? Int ?? 25))
        breakMinutes = min(30, max(1, defaults.object(forKey: "breakMinutes") as? Int ?? 5))
        accessory = defaults.string(forKey: "accessory") ?? "none"
        headAccessoriesVisible = defaults.object(forKey: "headAccessoriesVisible") as? Bool ?? true
        petScale = min(1.8, max(0.4, defaults.object(forKey: "petScale") as? Double ?? 1))
        dailyGoal = min(20000, max(100, defaults.object(forKey: "dailyGoal") as? Int ?? 1000))
        nickname = defaults.string(forKey: "nickname") ?? ""
        reactionsPaused = defaults.bool(forKey: "reactionsPaused")
        movement = MovementMode(rawValue: defaults.string(forKey: "movement") ?? "") ?? .roam
        greetings = defaults.object(forKey: "greetings") as? Bool ?? true
        userName = defaults.string(forKey: "userName") ?? ""
        edgeTraversal = defaults.bool(forKey: "edgeTraversal")
        musicReactive = defaults.bool(forKey: "musicReactive")
        musicLite = defaults.bool(forKey: "musicLite")
        petOpacity=min(1,max(0.2,defaults.object(forKey:"petOpacity") as? Double ?? 1))
        clickThrough=defaults.bool(forKey:"clickThrough")
        mirrorDock=defaults.bool(forKey:"mirrorDock")
    }
}

enum KeychainStore {
    static func save(_ value: String, key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pawsync.desktop", kSecAttrAccount as String: key]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query; attributes.forEach { item[$0] = $1 }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PawError.message("Could not save to Keychain.") }; return
        }
        guard result == errSecSuccess else { throw PawError.message("Could not update Keychain.") }
    }
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pawsync.desktop", kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pawsync.desktop", kSecAttrAccount as String: key] as CFDictionary)
    }
    static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw PawError.message("Secure random generation failed.") }
        return Data(bytes).base64EncodedString()
    }
}

extension Data {
    init?(base64URL: String) {
        let text = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: text + String(repeating: "=", count: (4 - text.count % 4) % 4))
    }
}
