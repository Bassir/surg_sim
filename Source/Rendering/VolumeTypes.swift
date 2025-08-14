import Foundation
import Metal
import simd

public typealias float2 = SIMD2<Float>
public typealias float3 = SIMD3<Float>
public typealias float4 = SIMD4<Float>
public typealias int3 = SIMD3<Int32>

// MARK: - Protocol for calculating struct sizes
protocol sizeable {
    static var size: Int { get }
}

extension sizeable {
    static var size: Int {
        return MemoryLayout<Self>.size
    }

    static var stride: Int {
        return MemoryLayout<Self>.stride
    }

    static func size(_ count: Int)->Int {
        return MemoryLayout<Self>.size * count
    }

    static func stride(_ count: Int)->Int {
        return MemoryLayout<Self>.stride * count
    }
}

extension Int32: sizeable {}
extension Float: sizeable {}
extension float2: sizeable {}
extension float3: sizeable {}
extension float4: sizeable {}

// MARK: - Basic Types

public struct RGBAColor: Codable, sizeable {
    public var r: Float = 0
    public var g: Float = 0
    public var b: Float = 0
    public var a: Float = 0

    public init(r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

public struct ColorPoint: Codable {
    public var dataValue: Float = 0
    public var colourValue: RGBAColor = RGBAColor()

    public init(dataValue: Float = 0, colourValue: RGBAColor = RGBAColor()) {
        self.dataValue = dataValue
        self.colourValue = colourValue
    }
}

public struct AlphaPoint: Codable, Equatable {
    public var dataValue: Float = 0
    public var alphaValue: Float = 0

    public init(dataValue: Float = 0, alphaValue: Float = 0) {
        self.dataValue = dataValue
        self.alphaValue = alphaValue
    }
}

// MARK: - Operators

internal func * (c: RGBAColor, v: Float) -> RGBAColor {
    RGBAColor(r: c.r * v, g: c.g * v, b: c.b * v, a: c.a * v)
}

internal func + (a: RGBAColor, b: RGBAColor) -> RGBAColor {
    RGBAColor(r: a.r + b.r, g: a.g + b.g, b: a.b + b.b, a: a.a + b.a)
}

// MARK: - Volume Uniforms

public struct VolumeUniforms: sizeable {
    var isLightingOn: Bool = true
    var isBackwardOn: Bool = false
    var method: Int32 = 1 // DVR
    var renderingQuality: Int32 = 512
    var voxelMinValue: Int32 = -1024
    var voxelMaxValue: Int32 = 3071
}

// MARK: - Tissue Layer System

public struct VTTissueLayer: Codable, Identifiable, Equatable {
    public var id: Int
    public var name: String
    public var densityRange: ClosedRange<Float>
    public var color: RGBAColor
    public var depth: Float // 0.0 (surface) to 1.0 (deep)
    public var isVisible: Bool = true
    public var hasBeenPainted: Bool = false
    public var paintMask: Data = Data() // Stores which voxels have been painted away
    
    public static func == (lhs: VTTissueLayer, rhs: VTTissueLayer) -> Bool {
        return lhs.id == rhs.id
    }
}

