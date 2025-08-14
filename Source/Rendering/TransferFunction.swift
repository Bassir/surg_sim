// Improved version from reference project tailored for macOS
import Foundation
import Metal
import simd

// Automatic tissue layer detected from density histogram
struct HistogramPeak {
    let dataValue: Float
    let frequency: Int
    let width: Float
}

public struct TransferFunction: Codable {
    var version: Int?
    var name: String = ""
    var colourPoints: [ColorPoint] = []
    var alphaPoints: [AlphaPoint] = []
    
    var min: Float = -1024
    var max: Float = 3071
    var shift: Float = 0
    
    // New procedural layer system
    var autoDetectedLayers: [VTTissueLayer] = []
    var useAutoSegmentation: Bool = true
    var globalOpacity: Float = 1.0
    var contrastBoost: Float = 1.0
    
    // Paint tool settings
    var brushSize: Float = 10.0
    var brushHardness: Float = 0.8
    var currentLayer: Int = 0
    
    static func createDefault() -> TransferFunction {
        var tf = TransferFunction()
        tf.name = "Default CT"
        
        // Default color points for CT-like visualization
        tf.colourPoints = [
            ColorPoint(dataValue: -1024, colourValue: RGBAColor(r: 0, g: 0, b: 0, a: 0)),
            ColorPoint(dataValue: -500, colourValue: RGBAColor(r: 0.2, g: 0.1, b: 0.1, a: 0.1)),
            ColorPoint(dataValue: 0, colourValue: RGBAColor(r: 0.5, g: 0.3, b: 0.2, a: 0.3)),
            ColorPoint(dataValue: 500, colourValue: RGBAColor(r: 0.8, g: 0.8, b: 0.7, a: 0.7)),
            ColorPoint(dataValue: 1000, colourValue: RGBAColor(r: 1, g: 1, b: 1, a: 1)),
            ColorPoint(dataValue: 3071, colourValue: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        ]
        
        // Default alpha points
        tf.alphaPoints = [
            AlphaPoint(dataValue: -1024, alphaValue: 0),
            AlphaPoint(dataValue: -500, alphaValue: 0.1),
            AlphaPoint(dataValue: 0, alphaValue: 0.3),
            AlphaPoint(dataValue: 500, alphaValue: 0.7),
            AlphaPoint(dataValue: 1000, alphaValue: 1),
            AlphaPoint(dataValue: 3071, alphaValue: 1)
        ]
        
        return tf
    }
    
    // Create a dynamic transfer function based on threshold and opacity
    static func createDynamic(threshold: Float, opacity: Float) -> TransferFunction {
        var tf = TransferFunction()
        tf.name = "Dynamic TF"
        
        // Create adaptive color points around the threshold
        let thresholdLow = threshold - 200
        let thresholdHigh = threshold + 200
        
        tf.colourPoints = [
            ColorPoint(dataValue: -1024, colourValue: RGBAColor(r: 0, g: 0, b: 0, a: 0)),
            ColorPoint(dataValue: thresholdLow, colourValue: RGBAColor(r: 0.1, g: 0.1, b: 0.2, a: 0.1)),
            ColorPoint(dataValue: threshold, colourValue: RGBAColor(r: 0.8, g: 0.6, b: 0.4, a: opacity)),
            ColorPoint(dataValue: thresholdHigh, colourValue: RGBAColor(r: 1.0, g: 0.9, b: 0.8, a: opacity)),
            ColorPoint(dataValue: 3071, colourValue: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        ]
        
        // Create adaptive alpha points
        tf.alphaPoints = [
            AlphaPoint(dataValue: -1024, alphaValue: 0),
            AlphaPoint(dataValue: thresholdLow, alphaValue: 0.05),
            AlphaPoint(dataValue: threshold, alphaValue: opacity * 0.7),
            AlphaPoint(dataValue: thresholdHigh, alphaValue: opacity),
            AlphaPoint(dataValue: 3071, alphaValue: 1)
        ]
        
        return tf
    }
    
    func get(device: MTLDevice) -> MTLTexture {
        let TEXTURE_WIDTH = 512
        let TEXTURE_HEIGHT = 2
        
        var tfCols = [RGBAColor](repeating: RGBAColor(), count: TEXTURE_WIDTH * TEXTURE_HEIGHT)
        
        // Sort points
        var cols = colourPoints.sorted(by: { $0.dataValue < $1.dataValue })
        var alps = alphaPoints.sorted(by: { $0.dataValue < $1.dataValue })
        
        // Apply shift
        cols = cols.map { var tmp = $0; tmp.dataValue += shift; return tmp }
        alps = alps.map { var tmp = $0; tmp.dataValue += shift; return tmp }
        
        // Add beginning and end
        if cols.count == 0 || cols.last!.dataValue < max {
            cols.append(ColorPoint(dataValue: max, colourValue: RGBAColor(r: 1, g: 1, b: 1, a: 1)))
        }
        if cols.first!.dataValue > min {
            cols.insert(ColorPoint(dataValue: min, colourValue: RGBAColor(r: 1, g: 1, b: 1, a: 1)), at: 0)
        }
        
        if alps.count == 0 || alps.last!.dataValue < max {
            alps.append(AlphaPoint(dataValue: max, alphaValue: 1))
        }
        if alps.first!.dataValue > min {
            alps.insert(AlphaPoint(dataValue: min, alphaValue: 0), at: 0)
        }
        
        var iCurrColor = 0
        var iCurrAlpha = 0
        
        for ix in 0..<TEXTURE_WIDTH {
            let t = Float(ix) / Float(TEXTURE_WIDTH - 1)
            let dataValue = min + t * (max - min)
            
            while iCurrColor < cols.count - 2,
                  normalize(cols[iCurrColor + 1].dataValue) < t {
                iCurrColor += 1
            }
            while iCurrAlpha < alps.count - 2,
                  normalize(alps[iCurrAlpha + 1].dataValue) < t {
                iCurrAlpha += 1
            }
            
            let leftCol = cols[iCurrColor]
            let rightCol = cols[iCurrColor + 1]
            let leftAlp = alps[iCurrAlpha]
            let rightAlp = alps[iCurrAlpha + 1]

            let tCol = (dataValue - leftCol.dataValue) / (rightCol.dataValue - leftCol.dataValue)
            let tAlp = (dataValue - leftAlp.dataValue) / (rightAlp.dataValue - leftAlp.dataValue)
            
            var pixCol = rightCol.colourValue * simd_clamp(tCol, 0, 1) + leftCol.colourValue * simd_clamp(1 - tCol, 0, 1)
            pixCol.a = rightAlp.alphaValue * simd_clamp(tAlp, 0, 1) + leftAlp.alphaValue * simd_clamp(1 - tAlp, 0, 1)
            
            for iy in 0..<TEXTURE_HEIGHT {
                tfCols[ix + iy * TEXTURE_WIDTH] = pixCol
            }
        }
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.pixelFormat = .rgba32Float
        textureDescriptor.width = TEXTURE_WIDTH
        textureDescriptor.height = TEXTURE_HEIGHT
        textureDescriptor.usage = .shaderRead
        
        let texture = device.makeTexture(descriptor: textureDescriptor)
        texture?.replace(region: MTLRegionMake2D(0, 0, TEXTURE_WIDTH, TEXTURE_HEIGHT),
                         mipmapLevel: 0,
                         slice: 0,
                         withBytes: tfCols,
                         bytesPerRow: RGBAColor.size * TEXTURE_WIDTH,
                         bytesPerImage: TEXTURE_WIDTH * TEXTURE_HEIGHT * RGBAColor.size)
        
        return texture!
    }
    
    func normalize(_ value: Float) -> Float {
        return (value - min) / (max - min)
    }
    
    // Auto-detect tissue layers from volume data histogram with spatial awareness
    mutating func autoSegmentLayers(volumeData: Data, dimensions: SIMD3<Int>) {
        guard !volumeData.isEmpty else { return }
        
        print("🔍 Auto-segmenting tissue layers with spatial awareness...")
        
        // Build 3D spatial-density analysis
        var densityHistogram: [Int: Int] = [:]
        var surfaceHighDensity: [Int] = []  // Track high-density surface voxels (likely staples)
        var deepHighDensity: [Int] = []     // Track high-density deep voxels (likely bone)
        
        let sampleSize = Swift.min(volumeData.count, 50000) // Reduced for spatial analysis
        let step = Swift.max(1, volumeData.count / sampleSize)
        
        for i in stride(from: 0, to: volumeData.count, by: step) {
            let rawValue = Int(volumeData[i])
            let scaledValue = Int((Float(rawValue) / 255.0) * 2000.0 - 1000.0) // Scale to HU range
            densityHistogram[scaledValue, default: 0] += 1
            
            // Spatial analysis - determine if this voxel is near surface or deep
            let z = i / (dimensions.x * dimensions.y)
            let y = (i % (dimensions.x * dimensions.y)) / dimensions.x
            let x = i % dimensions.x
            
            // Calculate distance from edges (normalized)
            let distFromSurface = Swift.min(
                Swift.min(x, dimensions.x - x),
                Swift.min(y, dimensions.y - y),
                Swift.min(z, dimensions.z - z)
            )
            let maxDist = Swift.min(dimensions.x, Swift.min(dimensions.y, dimensions.z)) / 2
            let depthRatio = Float(distFromSurface) / Float(maxDist)
            
            // High density classification based on spatial position
            if scaledValue > 800 { // High density threshold
                if depthRatio < 0.3 { // Near surface
                    surfaceHighDensity.append(scaledValue)
                } else { // Deep interior
                    deepHighDensity.append(scaledValue)
                }
            }
        }
        
        // Find density peaks for main tissue types
        let sortedDensities = densityHistogram.keys.sorted()
        var peaks: [Int] = []
        
        for i in 1..<(sortedDensities.count - 1) {
            let prev = densityHistogram[sortedDensities[i-1]] ?? 0
            let curr = densityHistogram[sortedDensities[i]] ?? 0
            let next = densityHistogram[sortedDensities[i+1]] ?? 0
            
            if curr > prev && curr > next && curr > 50 {
                peaks.append(sortedDensities[i])
            }
        }
        
        // Generate spatially-aware layers
        autoDetectedLayers.removeAll()
        peaks.sort()
        
        // First pass: create main tissue layers
        for (index, peak) in peaks.enumerated() {
            let nextPeak = (index + 1 < peaks.count) ? peaks[index + 1] : Int(self.max)
            let range = Float(peak)...Float(nextPeak)
            
            let layerName = generateLayerName(densityPeak: Float(peak))
            let layerColor = generateLayerColor(densityPeak: Float(peak))
            let depth = Float(index) / Float(Swift.max(1, peaks.count - 1))
            
            let layer = VTTissueLayer(
                id: index, 
                name: layerName, 
                densityRange: range, 
                color: layerColor, 
                depth: depth, 
                isVisible: true, 
                hasBeenPainted: false, 
                paintMask: Data()
            )
            autoDetectedLayers.append(layer)
        }
        
        // Second pass: Add specialized surface layers for staples/implants
        if !surfaceHighDensity.isEmpty {
            let avgSurfaceHU = surfaceHighDensity.reduce(0, +) / surfaceHighDensity.count
            let surfaceLayer = VTTissueLayer(
                id: autoDetectedLayers.count,
                name: "Surface Metal/Staples",
                densityRange: Float(avgSurfaceHU - 200)...Float(avgSurfaceHU + 200),
                color: RGBAColor(r: 0.9, g: 0.9, b: 1.0, a: 0.15), // Very transparent by default
                depth: 0.0, // Surface priority
                isVisible: true,
                hasBeenPainted: false,
                paintMask: Data()
            )
            autoDetectedLayers.insert(surfaceLayer, at: 0) // Insert at beginning for surface priority
            print("🏷️ Added surface metal layer: \(avgSurfaceHU) HU")
        }
        
        // Third pass: Add deep bone layer if needed
        if !deepHighDensity.isEmpty {
            let avgDeepHU = deepHighDensity.reduce(0, +) / deepHighDensity.count
            if avgDeepHU > 600 { // Bone-like density
                let boneLayer = VTTissueLayer(
                    id: autoDetectedLayers.count,
                    name: "Deep Bone",
                    densityRange: Float(avgDeepHU - 300)...Float(avgDeepHU + 300),
                    color: RGBAColor(r: 1.0, g: 0.95, b: 0.8, a: 0.8),
                    depth: 0.9, // Deep structure
                    isVisible: true,
                    hasBeenPainted: false,
                    paintMask: Data()
                )
                autoDetectedLayers.append(boneLayer)
                print("🦴 Added deep bone layer: \(avgDeepHU) HU")
            }
        }
        
        print("✅ Auto-detected \(autoDetectedLayers.count) spatially-aware tissue layers")
        for layer in autoDetectedLayers {
            print("   \(layer.name): \(layer.densityRange) (depth: \(layer.depth))")
        }
    }
    
    private func generateLayerName(densityPeak: Float) -> String {
        switch densityPeak {
        case ..<(-500): return "Air/Background"
        case -500..<(-100): return "Fat/Skin"
        case -100..<50: return "Soft Tissue"
        case 50..<200: return "Muscle/Organ"
        case 200..<600: return "Dense Tissue"
        case 600..<1200: return "Bone"
        default: return "Metal/Implant"
        }
    }
    
    private func generateLayerColor(densityPeak: Float) -> RGBAColor {
        switch densityPeak {
        case ..<(-500): return RGBAColor(r: 0.1, g: 0.1, b: 0.1, a: 0.05)
        case -500..<(-100): return RGBAColor(r: 0.8, g: 0.6, b: 0.4, a: 0.1)
        case -100..<50: return RGBAColor(r: 0.9, g: 0.4, b: 0.4, a: 0.3)
        case 50..<200: return RGBAColor(r: 0.7, g: 0.3, b: 0.3, a: 0.4)
        case 200..<600: return RGBAColor(r: 0.8, g: 0.7, b: 0.5, a: 0.6)
        case 600..<1200: return RGBAColor(r: 1.0, g: 0.95, b: 0.8, a: 0.8)
        default: return RGBAColor(r: 0.9, g: 0.9, b: 1.0, a: 0.2)
        }
    }
    
    // Paint away tissue at specific location
    mutating func paintAtLocation(x: Int, y: Int, z: Int, dimensions: SIMD3<Int>, erase: Bool = true) {
        guard currentLayer < autoDetectedLayers.count else { return }
        
        let index = z * dimensions.x * dimensions.y + y * dimensions.x + x
        let totalVoxels = dimensions.x * dimensions.y * dimensions.z
        
        // Apply brush with falloff
        let brushRadius = Int(brushSize)
        for dz in -brushRadius...brushRadius {
            for dy in -brushRadius...brushRadius {
                for dx in -brushRadius...brushRadius {
                    let newX = x + dx
                    let newY = y + dy
                    let newZ = z + dz
                    
                    guard newX >= 0 && newX < dimensions.x &&
                          newY >= 0 && newY < dimensions.y &&
                          newZ >= 0 && newZ < dimensions.z else { continue }
                    
                    let distance = sqrt(Float(dx*dx + dy*dy + dz*dz))
                    let falloff = Swift.max(0, 1.0 - (distance / brushSize))
                    let strength = pow(falloff, brushHardness)
                    
                    if strength > 0.1 {
                        let voxelIndex = newZ * dimensions.x * dimensions.y + newY * dimensions.x + newX
                        // Would update paint mask here if implemented
                    }
                }
            }
        }
    }

    public static func load(from url: URL) -> TransferFunction {
        let data = (try? Data(contentsOf: url)) ?? Data()
        return (try? JSONDecoder().decode(TransferFunction.self, from: data)) ?? TransferFunction.createDefault()
    }
}

