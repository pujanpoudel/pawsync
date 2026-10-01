import AppKit
import SpriteKit
import Metal
import ImageIO
import UniformTypeIdentifiers

/// One-time content bake. Runtime never synthesizes these sprite sheets.
@MainActor enum OriginalFrameExporter {
    private static let columns = 8
    private static let rows = 9
    private static let width = 192
    private static let height = 208

    private struct Pose {
        let image:CGImage
        let size:CGSize
    }

    private static func generatedPoses(for id:String)->[Pose]? {
        guard let url=Bundle.main.url(forResource:id,withExtension:"png",subdirectory:"OriginalPoseSheets"),
              let source=CGImageSourceCreateWithURL(url as CFURL,nil),
              let image=CGImageSourceCreateImageAtIndex(source,0,nil),
              image.width >= 900, image.height >= 900 else { return nil }
        guard let whole=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        whole.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        guard let wholeBytes=whole.data?.assumingMemoryBound(to:UInt8.self) else { return nil }
        var xCounts=[Int](repeating:0,count:image.width), yCounts=[Int](repeating:0,count:image.height)
        for y in 0..<image.height {
            for x in 0..<image.width where wholeBytes[(y*image.width+x)*4+3] > 24 {
                xCounts[x]+=1; yCounts[y]+=1
            }
        }
        func cut(_ counts:[Int],near fraction:Int)->Int {
            let target=counts.count*fraction/3
            let spread=counts.count/10
            let range=max(1,target-spread)..<min(counts.count-1,target+spread)
            return range.min { a,b in counts[a] == counts[b] ? abs(a-target) < abs(b-target) : counts[a] < counts[b] } ?? target
        }
        let xs=[0,cut(xCounts,near:1),cut(xCounts,near:2),image.width]
        let ys=[0,cut(yCounts,near:1),cut(yCounts,near:2),image.height]
        guard xs[0]<xs[1],xs[1]<xs[2],xs[2]<xs[3],ys[0]<ys[1],ys[1]<ys[2],ys[2]<ys[3] else { return nil }
        var result:[Pose]=[]
        for row in 0..<3 {
            for column in 0..<3 {
                let x0=xs[column], x1=xs[column+1]
                let y0=ys[row], y1=ys[row+1]
                let cell=CGRect(x:x0,y:y0,width:x1-x0,height:y1-y0)
                guard let crop=image.cropping(to:cell),
                      let context=CGContext(data:nil,width:crop.width,height:crop.height,bitsPerComponent:8,bytesPerRow:crop.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                context.draw(crop,in:CGRect(x:0,y:0,width:crop.width,height:crop.height))
                guard let bytes=context.data?.assumingMemoryBound(to:UInt8.self) else { return nil }
                var minX=crop.width,minY=crop.height,maxX=0,maxY=0
                for y in 0..<crop.height {
                    for x in 0..<crop.width where bytes[y*crop.width*4+x*4+3] > 24 {
                        minX=min(minX,x); minY=min(minY,y); maxX=max(maxX,x); maxY=max(maxY,y)
                    }
                }
                guard maxX-minX > 70,maxY-minY > 70,
                      let bounded=context.makeImage()?.cropping(to:CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)) else { return nil }
                result.append(Pose(image:bounded,size:CGSize(width:bounded.width,height:bounded.height)))
            }
        }
        return result.count == 9 ? result : nil
    }

    private static func drawGeneratedFrame(_ pose:[Pose],row:Int,frame:Int,into atlas:CGContext) {
        let keys:[Int] = [0,1,2,3,4,5,6,7,8]
        let index:Int
        switch row {
        case 0: index = frame == 5 ? 8 : 0
        case 1,2: index = frame.isMultiple(of:2) ? 1 : 2
        case 3: index = frame == 0 || frame == 7 ? 0 : 6
        case 4: index = frame == 0 ? 3 : frame < 4 ? 4 : 5
        case 5: index = frame < 5 ? 3 : 5
        case 6: index = frame == 4 ? 8 : 0
        case 7: index = 7
        default: index = frame >= 4 ? 8 : 0
        }
        let selected=pose[keys[index]]
        let heightLimit:CGFloat = row == 4 ? ((1...3).contains(frame) ? 150 : 170) : 186
        let scale=min(180/selected.size.width,heightLimit/selected.size.height)
        let size=CGSize(width:selected.size.width*scale,height:selected.size.height*scale)
        let phase=CGFloat(frame) * .pi / 4
        var lift:CGFloat=0
        if row == 4 {
            lift=[0,8,24,12,0,0,0,0][frame]
        } else if row == 1 || row == 2 {
            lift=2*abs(sin(phase))
        } else if row == 7 {
            lift=2*abs(sin(phase*2))
        }
        let baseY:CGFloat = row == 4 ? 8 : 10
        let x=CGFloat(frame*width)+(CGFloat(width)-size.width)/2
        let y=CGFloat((rows-1-row)*height)+baseY+lift
        atlas.saveGState()
        if row == 1 {
            atlas.translateBy(x:x+size.width,y:y)
            atlas.scaleBy(x:-1,y:1)
            atlas.draw(selected.image,in:CGRect(origin:.zero,size:size))
        } else { atlas.draw(selected.image,in:CGRect(x:x,y:y,width:size.width,height:size.height)) }
        atlas.restoreGState()
    }

    @MainActor private final class Capture {
        let renderer: SKRenderer
        let queue: any MTLCommandQueue
        let texture: any MTLTexture
        let scene = SKScene(size: CGSize(width: OriginalFrameExporter.width, height: OriginalFrameExporter.height))
        var time: TimeInterval = 1
        init() throws {
            guard let device=MTLCreateSystemDefaultDevice(), let queue=device.makeCommandQueue() else {
                throw PawError.message("Metal is unavailable for the sprite bake.")
            }
            self.queue=queue
            renderer=SKRenderer(device:device)
            let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:OriginalFrameExporter.width,height:OriginalFrameExporter.height,mipmapped:false)
            descriptor.usage = .renderTarget
            descriptor.storageMode = .shared
            guard let texture=device.makeTexture(descriptor:descriptor) else { throw PawError.message("Could not create sprite render target.") }
            self.texture=texture
            scene.backgroundColor = .clear
            renderer.scene=scene
            renderer.shouldCullNonVisibleNodes=true
            renderer.update(atTime:time)
        }
        func image() throws -> CGImage {
            let width=OriginalFrameExporter.width, height=OriginalFrameExporter.height
            time += 1.0/30.0
            renderer.update(atTime:time)
            let pass=MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture=texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
            guard let buffer=queue.makeCommandBuffer() else { throw PawError.message("Could not create sprite command buffer.") }
            renderer.render(withViewport:CGRect(x:0,y:0,width:width,height:height),commandBuffer:buffer,renderPassDescriptor:pass)
            buffer.commit(); buffer.waitUntilCompleted()
            if let error=buffer.error { throw error }
            var pixels=[UInt8](repeating:0,count:width*height*4)
            pixels.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0) }
            guard let provider=CGDataProvider(data:Data(pixels) as CFData),
                  let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {
                throw PawError.message("Could not read rendered sprite frame.")
            }
            return image
        }
    }

    static func run(directory:URL) throws {
        _=NSApplication.shared
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let capture=try Capture()
        for id in PetStore.rigIDs {
            let folder=directory.appendingPathComponent(id,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let poses=generatedPoses(for:id)
            capture.scene.removeAllChildren()
            let pet:PetSpriteNode?
            if poses == nil {
                let rig=try PetSpriteNode(manifest:PetStore.load(id),directory:PetStore.directory(for:id))
                rig.position=CGPoint(x:width/2,y:12)
                capture.scene.addChild(rig)
                pet=rig
            } else { pet=nil }
            guard let atlas=CGContext(data:nil,width:width*columns,height:height*rows,bitsPerComponent:8,bytesPerRow:width*columns*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw PawError.message("Could not allocate the sprite atlas.")
            }
            atlas.clear(CGRect(x:0,y:0,width:width*columns,height:height*rows))
            for row in 0..<rows {
                for frame in 0..<columns {
                    if let poses { drawGeneratedFrame(poses,row:row,frame:frame,into:atlas) }
                    else if let pet {
                        pet.setExportPose(row:row,frame:frame)
                        let image=try capture.image()
                        atlas.draw(image,in:CGRect(x:frame*width,y:(rows-1-row)*height,width:width,height:height))
                    }
                }
            }
            guard let image=atlas.makeImage(),
                  let destination=CGImageDestinationCreateWithURL(folder.appendingPathComponent("spritesheet.png") as CFURL,UTType.png.identifier as CFString,1,nil) else {
                throw PawError.message("Could not write the sprite atlas.")
            }
            CGImageDestinationAddImage(destination,image,nil)
            guard CGImageDestinationFinalize(destination) else { throw PawError.message("Could not finish sprite atlas.") }
            let metadata:[String:Any] = ["id":id,"displayName":PetStore.rigNames[id] ?? id,
                                          "description":"An original PawSync companion with OpenPets-compatible frame animations.",
                                          "spritesheetPath":"spritesheet.webp","spriteVersionNumber":1,
                                          "author":"PawSync"]
            try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("pet.json"),options:.atomic)
            if let sheet=Bundle.main.url(forResource:id,withExtension:"png",subdirectory:"CharacterSheets") {
                let target=folder.appendingPathComponent("character-sheet.png")
                try? FileManager.default.removeItem(at:target)
                try FileManager.default.copyItem(at:sheet,to:target)
            }
            if let source=Bundle.main.url(forResource:id,withExtension:"png",subdirectory:"OriginalPoseSheets") {
                let target=folder.appendingPathComponent("pose-sheet.png")
                try? FileManager.default.removeItem(at:target)
                try FileManager.default.copyItem(at:source,to:target)
            }
            print("Baked \(id): \(columns) × \(rows) transparent frames from \(poses == nil ? "rig" : "full-body pose art")")
        }
    }
}
