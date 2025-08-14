import Foundation
import simd

enum Math {
    static func lerp(_ a: Float, _ b: Float, _ w: Float) -> Float { a + w * (b - a) }
    static func lerp(_ a: float3, _ b: float3, _ w: Float) -> float3 { a + w * (b - a) }
} 