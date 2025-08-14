import Foundation
import simd

// Catmull-Rom spline interpolation
public func catmullRom(p0: Float, p1: Float, p2: Float, p3: Float, t: Float) -> Float {
    let t2 = t * t
    let t3 = t2 * t
    
    let a = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3
    let b = p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3
    let c = -0.5 * p0 + 0.5 * p2
    let d = p1
    
    return a * t3 + b * t2 + c * t + d
}

public func catmullRom(p0: RGBAColor, p1: RGBAColor, p2: RGBAColor, p3: RGBAColor, t: Float) -> RGBAColor {
    let r = catmullRom(p0: p0.r, p1: p1.r, p2: p2.r, p3: p3.r, t: t)
    let g = catmullRom(p0: p0.g, p1: p1.g, p2: p2.g, p3: p3.g, t: t)
    let b = catmullRom(p0: p0.b, p1: p1.b, p2: p2.b, p3: p3.b, t: t)
    let a = catmullRom(p0: p0.a, p1: p1.a, p2: p2.a, p3: p3.a, t: t)
    return RGBAColor(r: r, g: g, b: b, a: a)
} 