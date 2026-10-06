import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor enum PhotoPetChecks {
    private static func require(_ okay:Bool,_ text:String) throws {if !okay{throw PawError.message(text)}}
    static func run(directory:URL) throws {
        _=NSApplication.shared
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let photo=Data([0,1,2,3]),key="fixture-not-a-real-key"
        for provider in PetImageProvider.allCases {
            let request=try PetImageAPI.request(provider:provider,key:key,photo:photo)
            try require(request.url?.scheme == "https" && request.url?.query == nil,"A key can leak through a URL.")
            try require(request.httpMethod == "POST" && request.timeoutInterval == 180,"Incorrect image request method or timeout.")
            let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
            try require(provider == .gemini ? request.url!.path.contains(provider.model) : body["model"] as? String == provider.model,"Wrong provider model.")
            try require(!String(data:request.httpBody!,encoding:.utf8)!.contains(key),"A provider key leaked into the request body.")
            if provider == .gemini {
                try require(request.value(forHTTPHeaderField:"x-goog-api-key") == key && request.value(forHTTPHeaderField:"Authorization") == nil,"Gemini authentication is incorrect.")
                let response:[String:Any]=["candidates":[["content":["parts":[["thought":true,"inlineData":["data":Data([9]).base64EncodedString()]],["inlineData":["mimeType":"image/png","data":photo.base64EncodedString()]]]]]]]
                try require(PetImageAPI.image(from:try JSONSerialization.data(withJSONObject:response),provider:provider) == photo,"Gemini used a thought preview instead of its final image.")
            } else {
                try require(request.value(forHTTPHeaderField:"Authorization") == "Bearer "+key && request.value(forHTTPHeaderField:"x-goog-api-key") == nil,"Bearer authentication is incorrect.")
                try require(body[provider == .openAI ? "images":"image"] != nil,"Photo reference is missing.")
                let response:[String:Any]=["data":[["b64_json":photo.base64EncodedString()]]]
                try require(PetImageAPI.image(from:try JSONSerialization.data(withJSONObject:response),provider:provider) == photo,"Provider image did not decode.")
            }
            try require(PetImageAPI.image(from:Data("{\"error\":\"not authorized\"}".utf8),provider:provider) == nil,"A provider error became a pet.")
        }
        var rejected=false
        do{_=try PetImageAPI.request(provider:.grok,key:"bad\nheader",photo:photo)}catch{rejected=true}
        try require(rejected,"Invalid key header was accepted.")
        let fixture=try sheet(empty:false)
        let drafts=directory.appendingPathComponent("drafts")
        let draft=try PhotoPetAtlas.buildValidated(fixture,name:"Fixture friend",root:drafts)
        defer{try? FileManager.default.removeItem(at:drafts)}
        try require(draft.manifest.parts.count == 5 && draft.manifest.name == "Fixture friend","Generated parts do not match the rig contract.")
        for part in PetManifest.required {
            let decoded=try DecodedPetImage(url:draft.directory.appendingPathComponent(part+".png"))
            try require(decoded.width<=400 && decoded.height<=400,"Generated texture exceeds its memory budget.")
            try require(!decoded.mask.contains(x:0,y:0) && decoded.mask.contains(x:decoded.width/2,y:decoded.height/2),"Matte removal erased the part or left its background.")
            let color=decoded.color(x:decoded.width/2,y:decoded.height/2)
            try require(color.redComponent>0.95 && color.greenComponent>0.95 && color.blueComponent>0.95,"Background removal erased an enclosed white detail.")
        }
        rejected=false
        do{_=try PhotoPetAtlas.buildValidated(try sheet(empty:true),name:"Bad sheet",root:drafts)}catch{rejected=true}
        try require(rejected,"A sheet with missing parts was installed.")
        try require((try FileManager.default.contentsOfDirectory(atPath:drafts.path)).count == 1,"Failed generation left a partial pet on disk.")
        let renderer=try MotionChecks.Renderer()
        let pet=try PetSpriteNode(manifest:draft.manifest,directory:draft.directory)
        pet.position=CGPoint(x:130,y:24);renderer.scene.addChild(pet)
        var frames:[CGImage]=[]
        renderer.advance(0.03);frames.append(try renderer.capture())
        pet.typing();renderer.advance(0.16);frames.append(try renderer.capture())
        pet.cuddle();renderer.advance(0.32);frames.append(try renderer.capture())
        try MotionChecks.writeGrid([("Photo fixture",frames)],columns:["Assembled","Typing","Cuddle"],to:directory.appendingPathComponent("photo-rig.png"))
        print("Photo-pet checks passed: three authenticated provider contracts, final-image decoding, safe headers, five transparent parts, white-detail preservation, bounded textures, failure cleanup and native rig reactions. No live provider calls or real keys used.")
    }
    private static func sheet(empty:Bool) throws -> Data {
        let width=900,height=600
        let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(NSColor.magenta.cgColor);c.fill(CGRect(x:0,y:0,width:width,height:height))
        if !empty {
            for (x,y) in [(0,1),(1,1),(2,1),(0,0),(1,0)] {
                c.setFillColor(NSColor.systemBrown.cgColor);c.fillEllipse(in:CGRect(x:x*300+70,y:y*300+70,width:160,height:160))
                c.setFillColor(NSColor.white.cgColor);c.fillEllipse(in:CGRect(x:x*300+130,y:y*300+130,width:40,height:40))
            }
        }
        let data=NSMutableData(),dest=CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(dest,c.makeImage()!,nil);guard CGImageDestinationFinalize(dest) else{throw PawError.message("Fixture encoding failed.")};return data as Data
    }
}
