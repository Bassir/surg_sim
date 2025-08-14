import simd
import Foundation

// MARK: - Matrix Utility Functions for 3D Graphics

/// Convert degrees to radians
func radians(_ degrees: Float) -> Float {
    return degrees * Float.pi / 180.0
}

/// Convert radians to degrees
func degrees(_ radians: Float) -> Float {
    return radians * 180.0 / Float.pi
}

// MARK: - Identity Matrices

/// 4x4 Identity matrix
let matrix_identity_float4x4: simd_float4x4 = simd_float4x4(
    SIMD4<Float>(1, 0, 0, 0),
    SIMD4<Float>(0, 1, 0, 0),
    SIMD4<Float>(0, 0, 1, 0),
    SIMD4<Float>(0, 0, 0, 1)
)

/// 3x3 Identity matrix
let matrix_identity_float3x3: simd_float3x3 = simd_float3x3(
    SIMD3<Float>(1, 0, 0),
    SIMD3<Float>(0, 1, 0),
    SIMD3<Float>(0, 0, 1)
)

// MARK: - Perspective Projection

/// Create a perspective projection matrix
/// - Parameters:
///   - fovy: Field of view in radians
///   - aspect: Aspect ratio (width/height)
///   - near: Near clipping plane
///   - far: Far clipping plane
/// - Returns: Perspective projection matrix
func perspectiveMatrix(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let yScale = 1.0 / tan(fovy * 0.5)
    let xScale = yScale / aspect
    let zScale = far / (near - far)
    
    return simd_float4x4(
        SIMD4<Float>(xScale, 0, 0, 0),
        SIMD4<Float>(0, yScale, 0, 0),
        SIMD4<Float>(0, 0, zScale, -1),
        SIMD4<Float>(0, 0, near * zScale, 0)
    )
}

/// Create an orthographic projection matrix
/// - Parameters:
///   - left: Left clipping plane
///   - right: Right clipping plane
///   - bottom: Bottom clipping plane
///   - top: Top clipping plane
///   - near: Near clipping plane
///   - far: Far clipping plane
/// - Returns: Orthographic projection matrix
func orthographicMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
    let width = right - left
    let height = top - bottom
    let depth = far - near
    
    return simd_float4x4(
        SIMD4<Float>(2.0 / width, 0, 0, 0),
        SIMD4<Float>(0, 2.0 / height, 0, 0),
        SIMD4<Float>(0, 0, -2.0 / depth, 0),
        SIMD4<Float>(-(right + left) / width, -(top + bottom) / height, -(far + near) / depth, 1)
    )
}

// MARK: - Transformation Matrices

/// Create a translation matrix
/// - Parameters:
///   - x: Translation along X axis
///   - y: Translation along Y axis
///   - z: Translation along Z axis
/// - Returns: Translation matrix
func matrix4x4_translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    )
}

/// Create a translation matrix from a vector
/// - Parameter translation: Translation vector
/// - Returns: Translation matrix
func matrix4x4_translation(_ translation: SIMD3<Float>) -> simd_float4x4 {
    return matrix4x4_translation(translation.x, translation.y, translation.z)
}

/// Create a rotation matrix around an arbitrary axis
/// - Parameters:
///   - radians: Rotation angle in radians
///   - axis: Rotation axis (should be normalized)
/// - Returns: Rotation matrix
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cos(radians)
    let st = sin(radians)
    let ci = 1 - ct
    let x = unitAxis.x
    let y = unitAxis.y
    let z = unitAxis.z
    
    return simd_float4x4(
        SIMD4<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
        SIMD4<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0),
        SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

/// Create a rotation matrix around the X axis
/// - Parameter radians: Rotation angle in radians
/// - Returns: X-axis rotation matrix
func matrix4x4_rotation_x(_ radians: Float) -> simd_float4x4 {
    let cos_r = cos(radians)
    let sin_r = sin(radians)
    
    return simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, cos_r, sin_r, 0),
        SIMD4<Float>(0, -sin_r, cos_r, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

/// Create a rotation matrix around the Y axis
/// - Parameter radians: Rotation angle in radians
/// - Returns: Y-axis rotation matrix
func matrix4x4_rotation_y(_ radians: Float) -> simd_float4x4 {
    let cos_r = cos(radians)
    let sin_r = sin(radians)
    
    return simd_float4x4(
        SIMD4<Float>(cos_r, 0, -sin_r, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(sin_r, 0, cos_r, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

/// Create a rotation matrix around the Z axis
/// - Parameter radians: Rotation angle in radians
/// - Returns: Z-axis rotation matrix
func matrix4x4_rotation_z(_ radians: Float) -> simd_float4x4 {
    let cos_r = cos(radians)
    let sin_r = sin(radians)
    
    return simd_float4x4(
        SIMD4<Float>(cos_r, sin_r, 0, 0),
        SIMD4<Float>(-sin_r, cos_r, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

/// Create a scaling matrix
/// - Parameters:
///   - x: Scale factor along X axis
///   - y: Scale factor along Y axis
///   - z: Scale factor along Z axis
/// - Returns: Scaling matrix
func matrix4x4_scale(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4<Float>(x, 0, 0, 0),
        SIMD4<Float>(0, y, 0, 0),
        SIMD4<Float>(0, 0, z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

/// Create a uniform scaling matrix
/// - Parameter scale: Uniform scale factor
/// - Returns: Scaling matrix
func matrix4x4_scale(_ scale: Float) -> simd_float4x4 {
    return matrix4x4_scale(scale, scale, scale)
}

/// Create a scaling matrix from a vector
/// - Parameter scale: Scale vector
/// - Returns: Scaling matrix
func matrix4x4_scale(_ scale: SIMD3<Float>) -> simd_float4x4 {
    return matrix4x4_scale(scale.x, scale.y, scale.z)
}

// MARK: - View Matrices

/// Create a look-at view matrix
/// - Parameters:
///   - eye: Camera position
///   - center: Target position
///   - up: Up vector
/// - Returns: View matrix
func lookAtMatrix(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let f = normalize(center - eye)
    let s = normalize(cross(f, up))
    let u = cross(s, f)
    
    return simd_float4x4(
        SIMD4<Float>(s.x, u.x, -f.x, 0),
        SIMD4<Float>(s.y, u.y, -f.y, 0),
        SIMD4<Float>(s.z, u.z, -f.z, 0),
        SIMD4<Float>(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
    )
}

// MARK: - Matrix Operations

/// Extract the upper-left 3x3 matrix from a 4x4 matrix
/// - Parameter matrix: Input 4x4 matrix
/// - Returns: Upper-left 3x3 matrix
func matrix3x3_upper_left(_ matrix: simd_float4x4) -> simd_float3x3 {
    return simd_float3x3(
        SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
        SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
        SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
    )
}

/// Create a normal matrix from a model-view matrix
/// - Parameter modelView: Model-view matrix
/// - Returns: Normal matrix (inverse transpose of upper-left 3x3)
func normalMatrix(from modelView: simd_float4x4) -> simd_float3x3 {
    let upperLeft = matrix3x3_upper_left(modelView)
    return simd_transpose(simd_inverse(upperLeft))
}

// MARK: - Utility Functions

/// Clamp a value between min and max
/// - Parameters:
///   - value: Value to clamp
///   - min: Minimum value
///   - max: Maximum value
/// - Returns: Clamped value
func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
    return Swift.min(Swift.max(value, min), max)
}

/// Linear interpolation between two values
/// - Parameters:
///   - a: Start value
///   - b: End value
///   - t: Interpolation factor (0.0 to 1.0)
/// - Returns: Interpolated value
func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    return a + (b - a) * t
}

/// Smooth step interpolation
/// - Parameters:
///   - edge0: Left edge
///   - edge1: Right edge
///   - x: Input value
/// - Returns: Smooth step result
func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = clamp((x - edge0) / (edge1 - edge0), min: 0.0, max: 1.0)
    return t * t * (3.0 - 2.0 * t)
}

// MARK: - Vector Extensions

extension SIMD3 where Scalar == Float {
    /// Get the length (magnitude) of the vector
    var length: Float {
        return sqrt(x * x + y * y + z * z)
    }
    
    /// Get a normalized version of the vector
    var normalized: SIMD3<Float> {
        let len = length
        return len > 0 ? self / len : SIMD3<Float>(0, 0, 0)
    }
}

extension SIMD4 where Scalar == Float {
    /// Get the length (magnitude) of the vector (treating as 3D)
    var length: Float {
        return sqrt(x * x + y * y + z * z)
    }
    
    /// Get the xyz components as a SIMD3
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
} 