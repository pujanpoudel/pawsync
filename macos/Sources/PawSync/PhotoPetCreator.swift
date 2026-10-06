import AppKit
import ImageIO
import UniformTypeIdentifiers

enum PetImageProvider:String,CaseIterable,Identifiable {
    case gemini="Gemini",openAI="OpenAI",grok="Grok"
    var id:String {rawValue}
    var keyName:String {"pet-image-key."+rawValue.lowercased()}
    var model:String {switch self {case .gemini:return "gemini-3.1-flash-image";case .openAI:return "gpt-image-2.5-sunburst";case .grok:return "grok-imagine-image-2.0"}}
    var keyURL:URL {
        let address:String
        switch self {case .gemini:address="https://aistudio.google.com/api-keys";case .openAI:address="https://platform.openai.com/api-keys";case .grok:address="https://console.x.ai"}
        return URL(string:address)!
    }
}

/// Direct, opt-in image editing. Provider keys never visit PawSync's backend.
/// No automatic retry of a paid request: a lost response may already be billed.
enum PetImageAPI {
    static let prompt="""
    Use the attached pet photo as the identity reference. Preserve its species,
    coat markings, fur colors and natural eye colors. Make a lovable, rounded 2D
    cartoon desktop companion with soft brown outlines and natural, friendly eyes.
    Return ONE 3:2 image containing exactly a 3-column by 2-row sprite PART atlas.
    Every cell is equal size. Do NOT draw a complete pet in any cell.
    Top-left: ONLY the torso with its two hind feet, no head, forearms or tail.
    Top-middle: ONLY the complete head including ears and the face, neck at bottom.
    Top-right: ONLY the left forearm and paw, shoulder at top, paw at bottom.
    Bottom-left: ONLY the matching right forearm and paw, shoulder at top.
    Bottom-middle: ONLY the tail, base at its left side; for tailless pets use a tiny tuft.
    Bottom-right: leave completely empty.
    Each of the five pieces is centered in its cell, occupies about 70 percent of
    the cell, stays fully inside it, and has generous empty margins. The pieces
    have consistent art, light and perspective, ready to assemble as a front-facing
    standing pet. No labels, text, grid lines, shadows, props or accessories.
    The background must be transparent, or perfectly flat solid magenta #FF00FF
    if transparency is unavailable. Never draw a checkerboard or gradient.
    """
    static func request(provider:PetImageProvider,key:String,photo:Data) throws -> URLRequest {
        guard !key.isEmpty,key.count<4096,!key.contains("\n"),!key.contains("\r") else{throw PawError.message("Enter a valid API key for \(provider.rawValue).")}
        let image="data:image/jpeg;base64,"+photo.base64EncodedString()
        let url:URL,body:[String:Any]
        switch provider {
        case .openAI:
            url=URL(string:"https://api.openai.com/v1/images/edits")!
            body=["model":provider.model,"images":[["image_url":image]],"prompt":prompt,"n":1,"size":"1536x1024","background":"transparent","output_format":"png","quality":"medium"]
        case .gemini:
            url=URL(string:"https://generativelanguage.googleapis.com/v1/models/\(provider.model):generateContent")!
            body=["contents":[["parts":[["text":prompt],["inline_data":["mime_type":"image/jpeg","data":photo.base64EncodedString()]]]]],"generationConfig":["responseModalities":["TEXT","IMAGE"],"responseFormat":["image":["aspectRatio":"3:2","imageSize":"1K"]]]]
        case .grok:
            url=URL(string:"https://api.x.ai/v1/images/edits")!
            body=["model":provider.model,"prompt":prompt,"image":["url":image,"type":"image_url"],"n":1,"aspect_ratio":"3:2","response_format":"b64_json"]
        }
        var request=URLRequest(url:url,timeoutInterval:180)
        request.httpMethod="POST";request.httpBody=try JSONSerialization.data(withJSONObject:body)
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue(key,forHTTPHeaderField:provider == .gemini ? "x-goog-api-key":"Authorization")
        if provider != .gemini {request.setValue("Bearer "+key,forHTTPHeaderField:"Authorization")}
        return request
    }
    static func image(from data:Data,provider:PetImageProvider)->Data? {
        guard let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return nil}
        if provider == .gemini {
            let candidates=object["candidates"] as? [[String:Any]] ?? []
            for candidate in candidates {
                let content=candidate["content"] as? [String:Any]
                for part in content?["parts"] as? [[String:Any]] ?? [] where part["thought"] as? Bool != true {
                    if let inline=part["inlineData"] as? [String:Any] ?? part["inline_data"] as? [String:Any],let encoded=inline["data"] as? String {return Data(base64Encoded:encoded)}
                }
            }
        } else if let items=object["data"] as? [[String:Any]],let encoded=items.first?["b64_json"] as? String {return Data(base64Encoded:encoded)}
        return nil
    }
    static func generate(provider:PetImageProvider,key:String,photo:Data) async throws -> Data {
        let delegate=SameOriginDelegate()
        let configuration=URLSessionConfiguration.ephemeral
        configuration.urlCache=nil;configuration.httpCookieStorage=nil;configuration.timeoutIntervalForResource=190
        let session=URLSession(configuration:configuration,delegate:delegate,delegateQueue:nil)
        defer{session.invalidateAndCancel()}
        let request=try request(provider:provider,key:key,photo:photo)
        let (bytes,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse else{throw PawError.message("The provider returned an unreadable response.")}
        guard (200..<300).contains(http.statusCode) else {
            let message:String
            switch http.statusCode {
            case 401,403:message="Check your \(provider.rawValue) key and image-model access."
            case 429:message="Your provider's quota or rate limit was reached. Check billing, then retry later."
            case 400,404:message="The provider could not accept this image request. Check image-model availability for your account."
            default:message="The provider is unavailable (\(http.statusCode)). Please try again later."
            }
            // Do not display raw errors which can echo credentials or photo data.
            throw PawError.message(message)
        }
        guard response.expectedContentLength <= 48*1024*1024 else{throw PawError.message("The generated image is too large.")}
        var data=Data();data.reserveCapacity(1_048_576)
        for try await byte in bytes {
            data.append(byte)
            if data.count.isMultiple(of:8192){try Task.checkCancellation();guard data.count <= 48*1024*1024 else{throw PawError.message("The generated image is too large.")}}
        }
        guard let image=image(from:data,provider:provider),image.count <= 20*1024*1024 else{throw PawError.message("No usable image was returned. The provider may have declined the photo; choose another photo or retry.")}
        return image
    }
}

struct PhotoPetDraft {
    let manifest:PetManifest
    let directory:URL
}

/// Converts the provider's five separate parts into the existing skeletal atlas
/// contract. Background removal is local; there is no additional upload service.
enum PhotoPetAtlas {
    static func prepare(photo:Data) throws -> Data {
        guard let source=CGImageSourceCreateWithData(photo as CFData,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1536] as CFDictionary) else{throw PawError.message("Could not prepare your photo.")}
        let output=NSMutableData()
        guard let dest=CGImageDestinationCreateWithData(output,UTType.jpeg.identifier as CFString,1,nil) else{throw PawError.message("Could not prepare your photo.")}
        CGImageDestinationAddImage(dest,image,[kCGImageDestinationLossyCompressionQuality:0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else{throw PawError.message("Could not prepare your photo.")}
        return output as Data // strips photo metadata before sending
    }
    static func buildValidated(_ data:Data,name:String,root:URL) throws -> PhotoPetDraft {
        guard data.count <= 20*1024*1024,let source=CGImageSourceCreateWithData(data as CFData,nil),
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? Int,let height=properties[kCGImagePropertyPixelHeight] as? Int,
              width>=600,height>=400,width<=3072,height<=2048,abs(Double(width)/Double(height)-1.5)<0.05,
              let sheet=CGImageSourceCreateImageAtIndex(source,0,nil) else{throw PawError.message("The provider did not return the expected 3 × 2 part sheet. Try another generation; no pet was installed.")}
        let id=UUID().uuidString,directory=root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        do {
            let cells=[(0,0),(1,0),(2,0),(0,1),(1,1)]
            let display:[[Double]]=[[92,96],[116,104],[38,54],[38,54],[58,74]]
            let anchors:[[Double]]=[[0.5,0.12],[0.5,0.10],[0.5,0.9],[0.5,0.9],[0.1,0.5]]
            let offsets:[[Double]]=[[0,0],[0,70],[-35,60],[35,60],[-38,25]]
            var parts:[String:PetPart]=[:]
            for (i,key) in PetManifest.required.enumerated() {
                let cell=cells[i]
                guard let image=sheet.cropping(to:CGRect(x:cell.0*width/3,y:cell.1*height/2,width:width/3,height:height/2)) else{throw PawError.message("A generated pet part is missing.")}
                let png=try transparentPart(image)
                try png.write(to:directory.appendingPathComponent(key+".png"),options:.atomic)
                // Keep the provider's natural face. Eye landmarks are untrusted;
                // do not draw fake eyelids at guessed positions in generated pets.
                parts[key]=PetPart(file:key+".png",pngBase64:nil,anchor:anchors[i],parentOffset:offsets[i],textureRect:nil,displaySize:display[i],eyes:nil)
            }
            let manifest=PetManifest(id:id,name:String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80)),parts:parts,previewRect:nil)
            try manifest.validate();try JSONEncoder().encode(manifest).write(to:directory.appendingPathComponent("atlas.json"),options:.atomic)
            try preview(manifest:manifest,directory:directory).write(to:directory.appendingPathComponent("preview.png"),options:.atomic)
            return PhotoPetDraft(manifest:manifest,directory:directory)
        } catch {try? FileManager.default.removeItem(at:directory);throw error}
    }
    static func preview(manifest:PetManifest,directory:URL) throws -> Data {
        guard let c=CGContext(data:nil,width:220,height:220,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw PawError.message("Could not create a pet preview.")}
        for key in ["tail","body","head","left_paw","right_paw"] {
            guard let part=manifest.parts[key],let source=CGImageSourceCreateWithURL(directory.appendingPathComponent(key+".png") as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else{throw PawError.message("Could not create a pet preview.")}
            let size=part.displaySize ?? [Double(image.width),Double(image.height)]
            let scale=min(size[0]/Double(image.width),size[1]/Double(image.height)),w=Double(image.width)*scale,h=Double(image.height)*scale
            let offset=part.parentOffset ?? [0,0]
            c.draw(image,in:CGRect(x:110+offset[0]-w*part.anchor[0],y:24+offset[1]-h*part.anchor[1],width:w,height:h))
        }
        let data=NSMutableData()
        guard let image=c.makeImage(),let dest=CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil) else{throw PawError.message("Could not create a pet preview.")}
        CGImageDestinationAddImage(dest,image,nil);guard CGImageDestinationFinalize(dest) else{throw PawError.message("Could not create a pet preview.")};return data as Data
    }
    private static func transparentPart(_ image:CGImage) throws -> Data {
        let width=image.width,height=image.height
        var pixels=[UInt8](repeating:0,count:width*height*4)
        let okay=pixels.withUnsafeMutableBytes {buffer->Bool in
            guard let c=CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else{return false}
            c.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard okay else{throw PawError.message("Could not read the generated pet parts.")}
        let corner=Array(pixels.prefix(4))
        // Flood only border-connected flat background. White fur and interior eye
        // highlights survive, unlike removing every pixel matching a matte color.
        var seen=[Bool](repeating:false,count:width*height),queue:[Int]=[]
        func isBackground(_ i:Int)->Bool {
            let p=i*4
            if pixels[p+3]<30{return true}
            guard corner[3]>=30 else{return false}
            return (0..<3).allSatisfy{abs(Int(pixels[p+$0])-Int(corner[$0]))<48}
        }
        func enqueue(_ i:Int){if !seen[i] && isBackground(i){seen[i]=true;queue.append(i)}}
        for x in 0..<width{enqueue(x);enqueue((height-1)*width+x)}
        for y in 0..<height{enqueue(y*width);enqueue(y*width+width-1)}
        var at=0
        while at<queue.count {
            let i=queue[at];at+=1
            if i%width>0{enqueue(i-1)};if i%width<width-1{enqueue(i+1)}
            if i>=width{enqueue(i-width)};if i<(height-1)*width{enqueue(i+width)}
        }
        for i in queue{for c in 0..<4{pixels[i*4+c]=0}}
        var minX=width,minY=height,maxX=0,maxY=0,count=0,border=0
        for y in 0..<height {for x in 0..<width where pixels[(y*width+x)*4+3]>30 {
            minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y);count+=1
            if x<3 || y<3 || x>=width-3 || y>=height-3{border+=1}
        }}
        guard count>width*height/200,count<width*height*9/10,border<max(5,count/200) else{throw PawError.message("The generated parts overlap their cells or have no clear background. Try again; your photo and existing pets are unchanged.")}
        let png:Data?=pixels.withUnsafeMutableBytes {buffer in
            guard let c=CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue),
                  let clean=c.makeImage(),let trimmed=clean.cropping(to:CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)) else{return nil}
            let factor=min(1,400/Double(max(trimmed.width,trimmed.height)))
            let w=max(1,Int(Double(trimmed.width)*factor)),h=max(1,Int(Double(trimmed.height)*factor))
            guard let small=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
            small.interpolationQuality = .high;small.draw(trimmed,in:CGRect(x:0,y:0,width:w,height:h))
            guard let result=small.makeImage() else{return nil}
            let output=NSMutableData()
            guard let destination=CGImageDestinationCreateWithData(output,UTType.png.identifier as CFString,1,nil) else{return nil}
            CGImageDestinationAddImage(destination,result,nil);guard CGImageDestinationFinalize(destination) else{return nil};return output as Data
        }
        guard let png else{throw PawError.message("Could not prepare a transparent pet part.")};return png
    }
}

@MainActor final class PhotoPetCreator:ObservableObject {
    @Published private(set) var busy=false
    @Published private(set) var error=""
    @Published private(set) var draft:PhotoPetDraft?
    @Published private(set) var status=""
    var onInstalled:((String)->Void)?
    private var task:Task<Void,Never>?
    func saveKey(_ value:String,provider:PetImageProvider)->Bool {
        do {let key=value.trimmingCharacters(in:.whitespacesAndNewlines);guard !key.isEmpty,key.count<4096,!key.contains("\n"),!key.contains("\r") else{throw PawError.message("Enter your provider API key.")};try KeychainStore.save(key,key:provider.keyName);error="";return true}
        catch{self.error=error.localizedDescription;return false}
    }
    func generate(provider:PetImageProvider,photo:Data,name:String) {
        guard !busy else{return}
        guard let key=KeychainStore.read(provider.keyName) else{error="Add your \(provider.rawValue) API key first.";return}
        discard();busy=true;error="";status="Drawing your little friend with \(provider.rawValue)…"
        task=Task { [weak self] in
            guard let self else{return}
            defer{self.busy=false;self.status="";self.task=nil}
            do {
                let input=try await Task.detached(priority:.userInitiated){try PhotoPetAtlas.prepare(photo:photo)}.value
                let generated=try await PetImageAPI.generate(provider:provider,key:key,photo:input)
                try Task.checkCancellation();self.status="Making the parts ready to move…"
                let root=PetStore.pets.appendingPathComponent(".drafts")
                let result=try await Task.detached(priority:.userInitiated){try PhotoPetAtlas.buildValidated(generated,name:name.isEmpty ? "My little friend":name,root:root)}.value
                if Task.isCancelled{try? FileManager.default.removeItem(at:result.directory);throw CancellationError()}
                self.draft=result
            } catch is CancellationError {self.error="Generation canceled. Your provider may still bill a request already sent."}
            catch let error as URLError {self.error=error.code == .timedOut ? "The provider took too long. No pet was installed. Check your provider history before retrying; it may have completed the request.":"Could not reach your provider. Check your connection, then retry."}
            catch{self.error=error.localizedDescription}
        }
    }
    func install() {
        guard let draft,!busy else{return}
        do {try FileManager.default.moveItem(at:draft.directory,to:PetStore.pets.appendingPathComponent(draft.manifest.id));self.draft=nil;error="";onInstalled?(draft.manifest.id)}
        catch{self.error="Could not save your new pet. Please try adding it again."}
    }
    func discard(){if let draft{try? FileManager.default.removeItem(at:draft.directory)};draft=nil}
    func cancel(){task?.cancel()}
    func stop(){cancel();discard()}
}
