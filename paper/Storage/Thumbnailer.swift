import UIKit
import ImageIO

enum Thumbnailer {
    static func downsample(imageData: Data, maxDimension: CGFloat, scale: CGFloat = UIScreen.main.scale) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let src = CGImageSourceCreateWithData(imageData as CFData, options as CFDictionary) else { return nil }
        let maxPixel = maxDimension * scale
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary) else { return nil }
        let ui = UIImage(cgImage: cg)
        return ui.jpegData(compressionQuality: 0.8)
    }
}

