import AppKit
import SpriteKit
import Metal
import ImageIO
import UniformTypeIdentifiers

/// One-time content export: Windows/Linux use the exact macOS accessory artwork.
@MainActor enum PortableAssetExport {
    static func run(directory:URL) throws {
        _=NSApplication.shared;LibraryContent.load()
        try FileManager.default.createDirectory(at:directory.appendingPathComponent("items"),withIntermediateDirectories:true)
        guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else{throw PawError.message("Metal unavailable")}
        let renderer=SKRenderer(device:device),scene=SKScene(size:CGSize(width:160,height:160))
        scene.backgroundColor = .clear;renderer.scene=scene
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:160,height:160,mipmapped:false)
        descriptor.usage = .renderTarget;descriptor.storageMode = .shared
        guard let texture=device.makeTexture(descriptor:descriptor) else{throw PawError.message("Render target unavailable")}
        var items:[[String:Any]]=[]
        let all=FreeHat.all
        for (index,id) in (all.map(\.id)+["accessory.hat","accessory.glasses"]).enumerated() {
            guard let node=PetAccessories.make(id) else{throw PawError.message("Missing item \(id)")}
            scene.removeAllChildren();node.position=CGPoint(x:80,y:48);scene.addChild(node);renderer.update(atTime:Double(index+1))
            let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=texture;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
            guard let buffer=queue.makeCommandBuffer() else{throw PawError.message("Command buffer unavailable")}
            renderer.render(withViewport:CGRect(x:0,y:0,width:160,height:160),commandBuffer:buffer,renderPassDescriptor:pass);buffer.commit();buffer.waitUntilCompleted()
            if let error=buffer.error{throw error}
            var pixels=[UInt8](repeating:0,count:160*160*4)
            pixels.withUnsafeMutableBytes{texture.getBytes($0.baseAddress!,bytesPerRow:640,from:MTLRegionMake2D(0,0,160,160),mipmapLevel:0)}
            guard let provider=CGDataProvider(data:Data(pixels) as CFData),let image=CGImage(width:160,height:160,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:640,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent),let dest=CGImageDestinationCreateWithURL(directory.appendingPathComponent("items/"+id+".png") as CFURL,UTType.png.identifier as CFString,1,nil) else{throw PawError.message("Image export unavailable")}
            CGImageDestinationAddImage(dest,image,nil);guard CGImageDestinationFinalize(dest) else{throw PawError.message("Image export failed")}
            var value:[String:Any]
            if let item=all.first(where:{$0.id==id}),let json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(item)) as? [String:Any]{value=json}
            else{value=["id":id,"name":id == "accessory.hat" ? "Top hat":"Glasses","requiresSKU":id,"category":"Accessories","rarity":"Paid","weight":0]}
            value["file"]="items/"+id+".png";value["pivot"]=[80,112];items.append(value)
        }
        let achievements=LibraryAchievement.all.map{["id":$0.id,"title":$0.title,"detail":$0.detail,"icon":$0.icon,"key":$0.key,"goal":$0.goal] as [String:Any]}
        let secrets=SecretPair.all.map{["id":$0.id,"pet":$0.pet,"hat":$0.hat,"title":$0.title]}
        let pets=(PetStore.rigIDs.compactMap(PetStore.frameOriginal)+PetStore.imports).map { pet -> [String:Any] in
            let fits=(0..<pet.rows).map { row in (0..<8).map { col -> [String:Any] in
                let fit=PetAccessoryFit.frame(id:pet.id,row:row,column:col)
                return ["crown":[fit.crown.x+96,208-fit.crown.y],"scale":fit.scale,"glassesDrop":fit.glassesDrop]
            }}
            return ["id":pet.id,"name":pet.name,"unlock":LibraryProgress.petUnlock(pet.id),"fits":fits]
        }
        let features=NativeFeature.all.map{["id":$0.id,"name":$0.name,"enabled":$0.defaultEnabled,"phase":$0.phase] as [String:Any]}
        let payload:[String:Any]=["version":1,"items":items,"pets":pets,"features":features,"achievements":achievements,"secrets":secrets,"lines":LibraryContent.lines]
        try JSONSerialization.data(withJSONObject:payload,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("content.json"),options:.atomic)
        print("Exported \(items.count) exact native items, \(achievements.count) achievements and \(secrets.count) secrets.")
    }
}
