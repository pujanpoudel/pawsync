import AppKit
import ImageIO

/// One bit per pixel is enough for click-through. Do not retain a full RGBA
/// bitmap or create an NSColor for every pointer sample.
struct PetAlphaMask {
    let width:Int
    let height:Int
    let bits:Data
    func contains(x:Int,y:Int)->Bool {
        guard x >= 0,y >= 0,x < width,y < height else { return false }
        let offset=y*width+x
        return bits[offset >> 3] & (1 << (offset & 7)) != 0
    }
}

final class DecodedPetImage {
    let image:CGImage
    let width:Int
    let height:Int
    let mask:PetAlphaMask
    private let rgba:[UInt8]
    init(url:URL,maximumDimension:Int=3072) throws {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? Int,
              let height=properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,height > 0,width <= maximumDimension,height <= maximumDimension,width*height <= 8_000_000,
              let image=CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCache:false] as CFDictionary) else { throw PawError.message("Could not decode the pet image.") }
        self.width=width; self.height=height; self.image=image
        var pixels=[UInt8](repeating:0,count:width*height*4)
        let drawn=pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height)); return true
        }
        guard drawn else { throw PawError.message("Could not prepare the pet image.") }
        var bits=Data(repeating:0,count:(width*height+7)/8)
        for index in 0..<(width*height) where pixels[index*4+3] > 30 { bits[index >> 3] |= 1 << (index & 7) }
        mask=PetAlphaMask(width:width,height:height,bits:bits); rgba=pixels
    }
    func color(x:Int,y:Int)->NSColor {
        let index=(max(0,min(height-1,y))*width+max(0,min(width-1,x)))*4
        let alpha=max(1,Double(rgba[index+3]))
        return NSColor(calibratedRed:min(1,Double(rgba[index])/alpha),green:min(1,Double(rgba[index+1])/alpha),blue:min(1,Double(rgba[index+2])/alpha),alpha:1)
    }
}

/// Matches the pinned OpenPets reaction-animation-mapping.ts contract.
struct PetFrameSequence:Equatable {
    let row:Int
    let frames:Int
    let duration:TimeInterval
    let iterations:Int?
    func column(at elapsed:TimeInterval)->Int? {
        let elapsed=max(0,elapsed)
        if let iterations,elapsed >= duration*Double(iterations) { return nil }
        return min(frames-1,Int(elapsed.truncatingRemainder(dividingBy:duration)/(duration/Double(frames))))
    }
}
