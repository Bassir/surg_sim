import CoreGraphics
import Metal
import AppKit
import simd

class VolumeTextureFactory {
    var volumeData: Data
    var dimensions: SIMD3<Int>
    var resolution: SIMD3<Float>
    
    var scale: SIMD3<Float> {
        return SIMD3<Float>(
            resolution.x * Float(dimensions.x),
            resolution.y * Float(dimensions.y),
            resolution.z * Float(dimensions.z)
        )
    }
    
    init(volumeData: Data, dimensions: SIMD3<Int>) {
        self.volumeData = volumeData
        self.dimensions = dimensions
        // Default resolution for video frames
        self.resolution = SIMD3<Float>(0.001, 0.001, 0.001)
    }
    
    func generate(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Sint
        descriptor.usage = .shaderRead
        descriptor.width = dimensions.x
        descriptor.height = dimensions.y
        descriptor.depth = dimensions.z
        
        let texture = device.makeTexture(descriptor: descriptor)
        
        // Convert video frame data to Int16 format for shader compatibility
        let convertedData = convertToInt16Data(volumeData)
        
        let bytesPerRow = MemoryLayout<Int16>.size * descriptor.width
        let bytesPerImage = bytesPerRow * descriptor.height
        
        convertedData.withUnsafeBytes { bytes in
            texture?.replace(region: MTLRegionMake3D(0, 0, 0,
                                                     descriptor.width,
                                                     descriptor.height,
                                                     descriptor.depth),
                             mipmapLevel: 0,
                             slice: 0,
                             withBytes: bytes.baseAddress!,
                             bytesPerRow: bytesPerRow,
                             bytesPerImage: bytesPerImage)
        }
        
        return texture
    }
    
    private func convertToInt16Data(_ data: Data) -> Data {
        var int16Data = Data()
        int16Data.reserveCapacity(data.count / 4 * 2) // Assuming RGBA to grayscale conversion
        
        // Convert RGBA pixels to grayscale Int16 values
        for i in stride(from: 0, to: data.count, by: 4) {
            if i + 3 < data.count {
                let r = Int16(data[i])
                let g = Int16(data[i + 1])
                let b = Int16(data[i + 2])
                
                // Convert to grayscale using standard weights
                let grayscale = Int16((0.299 * Float(r) + 0.587 * Float(g) + 0.114 * Float(b)))
                
                // Scale to Hounsfield-like units (-1024 to 3071)
                let hounsfield = Int16(-1024 + (grayscale * 4095 / 255))
                
                withUnsafeBytes(of: hounsfield) { bytes in
                    int16Data.append(contentsOf: bytes)
                }
            }
        }
        
        return int16Data
    }
} 