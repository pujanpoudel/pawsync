import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct WalletSnapshot: Codable {
    let licensed: Bool
    let credits: Int
    let accessories: [String]
}

final class SameOriginDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let url = request.url,
              original.scheme == url.scheme, original.host == url.host, original.port == url.port else { completionHandler(nil); return }
        completionHandler(request)
    }
}

@MainActor final class APIClient {
    let config: AppConfiguration
    private let delegate = SameOriginDelegate()
    private lazy var session: URLSession = {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 30; options.timeoutIntervalForResource = 35
        options.urlCache = nil; options.httpCookieStorage = nil
        return URLSession(configuration: options, delegate: delegate, delegateQueue: nil)
    }()
    init(config: AppConfiguration) { self.config = config }
    func request(_ path: String, method: String = "GET", body: Data? = nil, contentType: String = "application/json", authenticated: Bool = true, idempotency: String? = nil) async throws -> Data {
        var request = URLRequest(url: config.apiBaseURL.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let token = KeychainStore.read("license") else { throw PawError.message("Restore your purchase before connecting.") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let idempotency { request.setValue(idempotency, forHTTPHeaderField: "Idempotency-Key") }
        var lastError: Error = PawError.message("The service is unavailable.")
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw PawError.message("Invalid server response.") }
                if (200..<300).contains(response.statusCode) { return data }
                let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                if response.statusCode == 401 { throw APIError.unauthorized }
                if response.statusCode >= 500 {
                    lastError = PawError.message(detail ?? "The service is temporarily unavailable.")
                } else { throw PawError.message(detail ?? "Request failed (\(response.statusCode)).") }
            } catch let error as URLError {
                guard [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code) else { throw error }
                lastError = error
            }
            if attempt < 2 { try await Task.sleep(nanoseconds: UInt64(pow(2, Double(attempt))) * 1_000_000_000) }
        }
        throw lastError
    }
    enum APIError: LocalizedError {
        case unauthorized
        var errorDescription: String? { "Your license was revoked or could not be verified. Restore your purchase to continue." }
    }
}

@MainActor final class PetWalletService: ObservableObject {
    @Published private(set) var licensed = false
    @Published private(set) var credits = 0
    @Published private(set) var accessories: [String] = []
    @Published var message = ""
    @Published private(set) var busy = false
    let api: APIClient
    init(api: APIClient) {
        self.api = api
        if let token = KeychainStore.read("license"), Self.validOfflineToken(token, publicKey: api.config.licensePublicKey) { licensed = true }
        if licensed { accessories = Self.tokenAccessories(KeychainStore.read("license") ?? "") }
        if licensed, let data = try? Data(contentsOf: PetStore.root.appendingPathComponent("wallet.json")),
           let snapshot = try? JSONDecoder().decode(WalletSnapshot.self, from: data) {
            // Credits are display-only offline; accessory ownership is separately signed in the token.
            credits = snapshot.credits
            accessories = Self.tokenAccessories(KeychainStore.read("license") ?? "")
        }
    }
    private static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3, let data = Data(base64URL: parts[1]) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    private static func tokenAccessories(_ token: String) -> [String] { claims(token)?["accessories"] as? [String] ?? [] }
    static func validOfflineToken(_ token: String, publicKey: String) -> Bool {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3, let raw = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              let signature = Data(base64URL: parts[2]),
              key.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)),
              let headerData = Data(base64URL: parts[0]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any], header["alg"] as? String == "EdDSA",
              let claims = claims(token), claims["iss"] as? String == "pawsync", claims["aud"] as? String == "pawsync-desktop",
              claims["licensed"] as? Bool == true, claims["sub"] is String else { return false }
        return true
    }
    func refresh() async {
        guard KeychainStore.read("license") != nil else { return }
        do {
            let data = try await api.request("v1/wallet")
            let snapshot = try JSONDecoder().decode(WalletSnapshot.self, from: data)
            licensed = snapshot.licensed; credits = snapshot.credits; accessories = snapshot.accessories
            if !licensed { KeychainStore.delete("license"); accessories = [] }
            else {
                let renewed = try await api.request("v1/license/renew", method: "POST")
                struct Renewal: Decodable { let token: String }
                let token = try JSONDecoder().decode(Renewal.self, from: renewed).token
                guard Self.validOfflineToken(token, publicKey: api.config.licensePublicKey) else { throw PawError.message("Invalid license signature.") }
                try KeychainStore.save(token, key: "license")
            }
            try FileManager.default.createDirectory(at: PetStore.root, withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: PetStore.root.appendingPathComponent("wallet.json"), options: .atomic)
            message = ""
        } catch APIClient.APIError.unauthorized {
            licensed = false; credits = 0; accessories = []; KeychainStore.delete("license")
            message = "License revoked. Restore your purchase to continue."
        } catch { message = "Offline — using your saved license. \(error.localizedDescription)" }
    }
    func requestRestore(email: String) async {
        busy = true; defer { busy = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["email": email])
            _ = try await api.request("v1/license/restore", method: "POST", body: body, authenticated: false)
            message = "If this email has a purchase, a one-time code is on its way."
        } catch { message = error.localizedDescription }
    }
    func completeRestore(email: String, code: String) async {
        busy = true; defer { busy = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["email": email, "code": code])
            let data = try await api.request("v1/license/restore/verify", method: "POST", body: body, authenticated: false)
            struct Restore: Decodable { let token: String }
            let token = try JSONDecoder().decode(Restore.self, from: data).token
            guard Self.validOfflineToken(token, publicKey: api.config.licensePublicKey) else { throw PawError.message("The license signature did not match this app.") }
            try KeychainStore.save(token, key: "license"); licensed = true
            await refresh()
        } catch { message = error.localizedDescription }
    }
    func checkout(_ sku: String) {
        guard let url = api.config.checkoutURLs[sku], url.scheme == "https" else { message = "Checkout has not been configured in this development build."; return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor final class CustomPetService: ObservableObject {
    @Published var selectedURL: URL?
    @Published var preview: NSImage?
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var progress = ""
    @Published private(set) var canRetry = false
    @Published var customPets = PetStore.customPets()
    private var requestID = UUID().uuidString
    private let api: APIClient
    private let wallet: PetWalletService
    var onInstalled: ((String) -> Void)?
    init(api: APIClient, wallet: PetWalletService) { self.api = api; self.wallet = wallet }
    func select(_ url: URL) {
        do {
            let data = try validate(url)
            selectedURL = url; error = nil; requestID = UUID().uuidString; canRetry = false
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 320, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                preview = NSImage(cgImage: thumbnail, size: .zero)
            }
        } catch { self.error = error.localizedDescription; selectedURL = nil; preview = nil }
    }
    func choosePhoto() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.jpeg, .png, .heic]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { select(url) }
    }
    func validate(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, (size.fileSize ?? 0) <= 15 * 1024 * 1024, (size.fileSize ?? 0) > 0 else { throw PawError.message("Choose an image smaller than 15 MB.") }
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source), let type = UTType(sourceType as String),
              [UTType.jpeg, .png, .heic].contains(where: { type.conforms(to: $0) }),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = metadata[kCGImagePropertyPixelWidth] as? Int, let height = metadata[kCGImagePropertyPixelHeight] as? Int,
              width >= 64, height >= 64, width <= 8192, height <= 8192, width * height <= 40_000_000 else {
            throw PawError.message("Use a JPEG, PNG or HEIC photo between 64 and 8192 pixels, with at most 40 megapixels.")
        }
        return data
    }
    func reloadPets() {customPets=PetStore.customPets();PetStore.invalidateImports()}
    func generate() async {
        guard let url = selectedURL, !busy else { return }
        guard wallet.licensed, wallet.credits > 0 || canRetry else { error = "Restore your license and add generation credits to continue."; return }
        busy = true; error = nil; progress = "Giving your companion a new look…"
        defer { busy = false; progress = "" }
        do {
            let data = try validate(url)
            let boundary = "PawSync-\(UUID().uuidString)"
            var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"pet.photo\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
            body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            canRetry = true
            let response = try await api.request("v1/pet/vectorize", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)", idempotency: requestID)
            guard response.count <= 10 * 1024 * 1024 else { throw PawError.message("The generated pet package is too large.") }
            let manifest = try JSONDecoder().decode(PetManifest.self, from: response)
            try manifest.validate()
            let staging = PetStore.pets.appendingPathComponent(".staging-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            var savedParts: [String: PetPart] = [:]
            for key in PetManifest.required {
                let part = manifest.parts[key]!
                guard let encoded = part.pngBase64, let png = Data(base64Encoded: encoded), png.count < 2 * 1024 * 1024,
                      let source = CGImageSourceCreateWithData(png as CFData, nil),
                      (CGImageSourceGetType(source) as String?) == UTType.png.identifier,
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width <= 512, image.height <= 512 else { throw PawError.message("The service returned an invalid \(key) image.") }
                try png.write(to: staging.appendingPathComponent("\(key).png"), options: .atomic)
                savedParts[key] = PetPart(file: "\(key).png", pngBase64: nil, anchor: part.anchor, parentOffset: part.parentOffset, textureRect: nil, displaySize: nil, eyes: nil)
            }
            let saved = PetManifest(id: manifest.id, name: manifest.name, parts: savedParts, previewRect: nil)
            try JSONEncoder().encode(saved).write(to: staging.appendingPathComponent("atlas.json"), options: .atomic)
            let destination = PetStore.pets.appendingPathComponent(saved.id)
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.moveItem(at: staging, to: destination) }
            customPets = PetStore.customPets(); onInstalled?(saved.id)
            requestID = UUID().uuidString; canRetry = false
            await wallet.refresh()
        } catch { self.error = error.localizedDescription; await wallet.refresh() }
    }
}
