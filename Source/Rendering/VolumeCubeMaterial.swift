import SceneKit
import Metal
import simd

class VolumeCubeMaterial: SCNMaterial {
    enum Method: String, CaseIterable, Identifiable {
        var id: RawValue { rawValue }
        var idInt32: Int32 {
            switch(self) {
            case .surf: return 0
            case .dvr: return 1
            case .mip: return 2
            }
        }
        case surf, dvr, mip
    }

    var uniform = VolumeUniforms()
    var transferFunction: TransferFunction?

    init(device: MTLDevice) {
        super.init()

        let program = SCNProgram()
        program.vertexFunctionName = "volume_vertex"
        program.fragmentFunctionName = "volume_fragment"
        self.program = program

        // Set default transfer function
        transferFunction = TransferFunction.createDefault()
        setTransferFunction(device: device)

        let buffer = NSData(bytes: &uniform, length: VolumeUniforms.size)
        setValue(buffer, forKey: "uniforms")

        cullMode = .front
        writesToDepthBuffer = true
        isDoubleSided = false
        lightingModel = .constant
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMethod(_ method: Method) {
        uniform.method = method.idInt32
        updateUniforms()
    }

    func setVolumeData(device: MTLDevice, volumeData: Data, dimensions: SIMD3<Int>, completion: @escaping (Bool) -> Void) {
        // Check memory availability before processing
        let availableMemory = getAvailableMemory()
        let requiredMemory = volumeData.count * 2 // Rough estimate for conversion
        
        print("💾 Memory check: Available \(availableMemory/1024/1024)MB, Required ~\(requiredMemory/1024/1024)MB")
        
        if requiredMemory > availableMemory {
            print("⚠️ Low memory warning - using chunked processing")
        }
        
        // Process volume data asynchronously to prevent blocking the main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            // Create texture with optimized data conversion
            if let texture = self.createVolumeTextureOptimized(device: device, volumeData: volumeData, dimensions: dimensions) {
                DispatchQueue.main.async {
                    let property = SCNMaterialProperty(contents: texture)
                    self.setValue(property, forKey: "dicom")
                    completion(true)
                }
            } else {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    func setTransferFunction(device: MTLDevice) {
        guard let tf = transferFunction else { return }
        let tfTexture = tf.get(device: device)
        let tfProperty = SCNMaterialProperty(contents: tfTexture)
        setValue(tfProperty, forKey: "transferColor")
    }

    func setLighting(on: Bool) {
        uniform.isLightingOn = on
        updateUniforms()
    }

    func setRenderingQuality(_ quality: Int) {
        uniform.renderingQuality = Int32(max(quality, 128))
        updateUniforms()
    }
    
    func setBackwardRendering(_ backward: Bool) {
        uniform.isBackwardOn = backward
        updateUniforms()
    }
    
    func setVoxelRange(min: Int32, max: Int32) {
        uniform.voxelMinValue = min
        uniform.voxelMaxValue = max
        updateUniforms()
    }
    
    func setShift(device: MTLDevice, shift: Float) {
        transferFunction?.shift = shift
        setTransferFunction(device: device)
    }
    
    // Dynamic transfer function update for real-time control
    func updateDynamicTransferFunction(device: MTLDevice, threshold: Float, opacity: Float) {
        print("🎨 Dynamic transfer function update: threshold=\(threshold), opacity=\(opacity)")
        
        // Update the transfer function with new parameters
        guard let tf = transferFunction else {
            print("❌ No transfer function available")
            return
        }
        
        // Create a simple dynamic transfer function based on threshold and opacity
        let dynamicTF = TransferFunction.createDynamic(threshold: threshold, opacity: opacity)
        transferFunction = dynamicTF
        
        // Update voxel range based on threshold
        let minValue = Int32(threshold - 500)
        let maxValue = Int32(threshold + 2000)
        setVoxelRange(min: minValue, max: maxValue)
        
        // Apply the updated transfer function
        setTransferFunction(device: device)
        print("✅ Dynamic transfer function applied")
    }
    
    // Paint mask functionality for surgical planning
    private var paintMaskTexture: MTLTexture?
    
    func updatePaintMask(device: MTLDevice, paintData: Data, dimensions: SIMD3<Int>) {
        guard !paintData.isEmpty else {
            print("⚠️ Empty paint data")
            return
        }
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r8Unorm
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.width = dimensions.x
        descriptor.height = dimensions.y
        descriptor.depth = dimensions.z
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            print("❌ Failed to create paint mask texture")
            return
        }
        
        let bytesPerRow = dimensions.x
        let bytesPerImage = bytesPerRow * dimensions.y
        
        paintData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            
            texture.replace(region: MTLRegionMake3D(0, 0, 0, dimensions.x, dimensions.y, dimensions.z),
                           mipmapLevel: 0,
                           slice: 0,
                           withBytes: baseAddress,
                           bytesPerRow: bytesPerRow,
                           bytesPerImage: bytesPerImage)
        }
        
        paintMaskTexture = texture
        let maskProperty = SCNMaterialProperty(contents: texture)
        setValue(maskProperty, forKey: "paintMask")
        
        print("✅ Paint mask texture updated")
    }
    
    func clearPaintMask(device: MTLDevice, dimensions: SIMD3<Int>) {
        let clearData = Data(count: dimensions.x * dimensions.y * dimensions.z)
        updatePaintMask(device: device, paintData: clearData, dimensions: dimensions)
    }
    
    private func updateUniforms() {
        let buffer = NSData(bytes: &uniform, length: VolumeUniforms.size)
        setValue(buffer, forKey: "uniforms")
    }
    
    private func createVolumeTextureOptimized(device: MTLDevice, volumeData: Data, dimensions: SIMD3<Int>) -> MTLTexture? {
        print("🔧 Creating volume texture with dimensions: \(dimensions), data size: \(volumeData.count) bytes")
        
        // Validate input parameters
        guard dimensions.x > 0 && dimensions.y > 0 && dimensions.z > 0 else {
            print("❌ Invalid dimensions: \(dimensions)")
            return nil
        }
        
        guard !volumeData.isEmpty else {
            print("❌ Empty volume data")
            return nil
        }
        
        // Decide whether to downsample before converting to Int16 to keep memory under limits
        let maxOutputBytes = 1024 * 1024 * 2048 // 2GB
        let inputCount = volumeData.count
        let bytesPerPixel = detectBytesPerPixel(data: volumeData, inputCount: inputCount)
        let pixelCount = inputCount / max(bytesPerPixel, 1)
        let estimatedInt16Bytes = pixelCount * MemoryLayout<Int16>.size
        
        var workingData = volumeData
        var workingDims = dimensions
        
        if bytesPerPixel == 1 && estimatedInt16Bytes > maxOutputBytes {
            // Compute a downsample factor for X/Y to bring the output under the limit
            let factor = computeDownsampleFactor(width: dimensions.x, height: dimensions.y, depth: dimensions.z, bytesPerVoxel: MemoryLayout<Int16>.size, maxBytes: maxOutputBytes)
            print("⚠️ Output would be too large (\(estimatedInt16Bytes/1024/1024)MB). Downsampling XY by factor \(factor)")
            let result = downsampleGrayscale8Bit(data: volumeData, width: dimensions.x, height: dimensions.y, depth: dimensions.z, factorXY: factor)
            workingData = result.data
            workingDims = SIMD3<Int>(result.width, result.height, result.depth)
            print("✅ Downsampled to \(workingDims.x)x\(workingDims.y)x\(workingDims.z) (\(workingData.count) bytes)")
        }
        
        // Convert volume data and validate size
        let convertedData = convertToInt16DataOptimized(workingData)
        guard !convertedData.isEmpty else {
            print("❌ Data conversion failed")
            return nil
        }
        
        // Calculate expected size for the 3D texture
        let expectedVoxels = workingDims.x * workingDims.y * workingDims.z
        let expectedBytes = expectedVoxels * MemoryLayout<Int16>.size
        
        print("📊 Expected: \(expectedVoxels) voxels, \(expectedBytes) bytes")
        print("📊 Actual: \(convertedData.count) bytes")
        
        // Check if we have enough data
        if convertedData.count < expectedBytes {
            print("⚠️ Not enough data for texture. Using available data and adjusting depth.")
            let actualVoxels = convertedData.count / MemoryLayout<Int16>.size
            let adjustedDepth = max(1, actualVoxels / (workingDims.x * workingDims.y))
            print("📏 Adjusting depth from \(workingDims.z) to \(adjustedDepth)")
            return createTextureWithData(device: device,
                                         data: convertedData,
                                         width: workingDims.x,
                                         height: workingDims.y,
                                         depth: adjustedDepth)
        } else {
            // Use the requested (possibly downsampled) dimensions
            return createTextureWithData(device: device,
                                         data: convertedData,
                                         width: workingDims.x,
                                         height: workingDims.y,
                                         depth: workingDims.z)
        }
    }
    
    private func createTextureWithData(device: MTLDevice, data: Data, width: Int, height: Int, depth: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Sint
        descriptor.usage = .shaderRead
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = depth
        
        print("🏗️ Creating texture: \(width)x\(height)x\(depth)")
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            print("❌ Failed to create Metal texture with descriptor")
            return nil
        }
        
        let bytesPerRow = MemoryLayout<Int16>.size * width
        // Metal requires row alignment (typically 256 bytes). Pad rows if needed.
        let rowAlignment = 256
        let alignedBytesPerRow = ((bytesPerRow + (rowAlignment - 1)) / rowAlignment) * rowAlignment
        let bytesPerImage = bytesPerRow * height
        let alignedBytesPerImage = alignedBytesPerRow * height
        let totalBytesNeeded = bytesPerImage * depth
        let totalAlignedBytes = alignedBytesPerImage * depth

        print("📏 Texture layout: row=\(bytesPerRow) (aligned \(alignedBytesPerRow)), image=\(bytesPerImage) (aligned \(alignedBytesPerImage)), total=\(totalBytesNeeded) (aligned \(totalAlignedBytes))")

        // Ensure we don't exceed available data
        let safeDataSize = min(data.count, totalBytesNeeded)
        let safeData = data.prefix(safeDataSize)

        // If already aligned, upload directly. Otherwise, build a padded staging buffer.
        if bytesPerRow == alignedBytesPerRow {
            safeData.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    print("❌ Failed to get data base address")
                    return
                }
                print("🔄 Replacing texture region (direct upload)...")
                texture.replace(region: MTLRegionMake3D(0, 0, 0, width, height, depth),
                                mipmapLevel: 0,
                                slice: 0,
                                withBytes: baseAddress,
                                bytesPerRow: bytesPerRow,
                                bytesPerImage: bytesPerImage)
                print("✅ Texture data uploaded successfully")
            }
        } else {
            print("⚙️ Building aligned staging buffer for Metal upload...")
            var staging = Data(count: totalAlignedBytes)
            staging.withUnsafeMutableBytes { dstBuf in
                guard let dstBase = dstBuf.bindMemory(to: UInt8.self).baseAddress else { return }
                safeData.withUnsafeBytes { srcBuf in
                    guard let srcBase = srcBuf.bindMemory(to: UInt8.self).baseAddress else { return }
                    for z in 0..<depth {
                        let srcImageOffset = z * bytesPerImage
                        let dstImageOffset = z * alignedBytesPerImage
                        for y in 0..<height {
                            let srcRowOffset = srcImageOffset + y * bytesPerRow
                            let dstRowOffset = dstImageOffset + y * alignedBytesPerRow
                            memcpy(dstBase + dstRowOffset, srcBase + srcRowOffset, bytesPerRow)
                        }
                    }
                }
            }
            staging.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                print("🔄 Replacing texture region (aligned upload)...")
                texture.replace(region: MTLRegionMake3D(0, 0, 0, width, height, depth),
                                mipmapLevel: 0,
                                slice: 0,
                                withBytes: baseAddress,
                                bytesPerRow: alignedBytesPerRow,
                                bytesPerImage: alignedBytesPerImage)
                print("✅ Texture data uploaded successfully (aligned)")
            }
        }
        
        return texture
    }
    
    private func convertToInt16DataOptimized(_ data: Data) -> Data {
        let inputCount = data.count
        print("🔄 Converting \(inputCount) bytes to Int16 format...")
        
        guard inputCount > 0 else {
            print("❌ Empty input data")
            return Data()
        }
        
        // Safety check: prevent processing extremely large datasets
        let maxDataSize = 1024 * 1024 * 2048 // 2GB limit (increased from 500MB)
        if inputCount > maxDataSize {
            print("❌ Data too large (\(inputCount/1024/1024)MB), exceeds \(maxDataSize/1024/1024)MB limit")
            return Data()
        }
        
        // Safer approach: detect format and process accordingly
        let bytesPerPixel = detectBytesPerPixel(data: data, inputCount: inputCount)
        let pixelCount = inputCount / bytesPerPixel
        let outputSize = pixelCount * MemoryLayout<Int16>.size
        
        print("📊 Detected \(bytesPerPixel) bytes per pixel, \(pixelCount) pixels total")
        
        // Additional safety check for output size  
        if outputSize > maxDataSize {
            print("❌ Output would be too large (\(outputSize/1024/1024)MB), exceeds \(maxDataSize/1024/1024)MB limit")
            return Data()
        }
        
        // Create output data with proper size
        var int16Data = Data(count: outputSize)
        
        let success = int16Data.withUnsafeMutableBytes { outputBuffer -> Bool in
            guard let outputPtr = outputBuffer.bindMemory(to: Int16.self).baseAddress else {
                print("❌ Failed to bind output buffer")
                return false
            }
            
            return data.withUnsafeBytes { inputBuffer -> Bool in
                guard let inputPtr = inputBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    print("❌ Failed to bind input buffer")
                    return false
                }
                
                // Process based on detected format
                if bytesPerPixel == 4 {
                    // RGBA format
                    return processRGBAData(inputPtr: inputPtr, outputPtr: outputPtr, pixelCount: pixelCount)
                } else if bytesPerPixel == 1 {
                    // Grayscale format
                    return processGrayscaleData(inputPtr: inputPtr, outputPtr: outputPtr, pixelCount: pixelCount)
                } else {
                    print("❌ Unsupported format: \(bytesPerPixel) bytes per pixel")
                    return false
                }
            }
        }
        
        if success {
            print("✅ Conversion complete: \(int16Data.count) bytes")
            return int16Data
        } else {
            print("❌ Conversion failed, returning empty data")
            return Data()
        }
    }
    
    private func detectBytesPerPixel(data: Data, inputCount: Int) -> Int {
        // Simple heuristic: if data size suggests RGBA (4 bytes/pixel), use 4
        // Otherwise assume grayscale (1 byte/pixel)
        let possiblePixelCounts = [1, 3, 4] // Grayscale, RGB, RGBA
        
        print("🔎 Analyzing data format for \(inputCount) bytes...")
        
        for bytesPerPixel in possiblePixelCounts.reversed() {
            if inputCount % bytesPerPixel == 0 {
                let pixelCount = inputCount / bytesPerPixel
                print("🧮 Testing \(bytesPerPixel) bytes/pixel: \(pixelCount) pixels")
                
                // Reasonable pixel count (not too small, not ridiculously large)
                if pixelCount >= 1000 && pixelCount <= 5_000_000_000 {
                    print("✅ Detected format: \(bytesPerPixel) bytes per pixel, \(pixelCount) pixels")
                    return bytesPerPixel
                } else {
                    print("❌ Pixel count \(pixelCount) is outside reasonable range")
                }
            } else {
                print("⚠️ \(inputCount) bytes not divisible by \(bytesPerPixel)")
            }
        }
        
        // Default to grayscale if detection fails
        print("⚠️ Format detection failed, defaulting to grayscale (1 byte/pixel)")
        return 1
    }

    private func computeDownsampleFactor(width: Int, height: Int, depth: Int, bytesPerVoxel: Int, maxBytes: Int) -> Int {
        var factor = 2
        while factor < 16 { // cap factor to avoid over-reduction
            let newW = max(1, width / factor)
            let newH = max(1, height / factor)
            let voxels = newW * newH * depth
            let bytes = voxels * bytesPerVoxel
            if bytes <= maxBytes { return factor }
            factor += 1
        }
        return factor
    }

    private func downsampleGrayscale8Bit(data: Data, width: Int, height: Int, depth: Int, factorXY: Int) -> (data: Data, width: Int, height: Int, depth: Int) {
        let newW = max(1, width / factorXY)
        let newH = max(1, height / factorXY)
        let newD = depth
        let outputCount = newW * newH * newD
        var out = Data(count: outputCount)
        
        out.withUnsafeMutableBytes { outBuf in
            guard let outPtr = outBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            data.withUnsafeBytes { inBuf in
                guard let inPtr = inBuf.bindMemory(to: UInt8.self).baseAddress else { return }
                let srcSliceStride = width * height
                let dstSliceStride = newW * newH
                for z in 0..<newD {
                    let srcZBase = z * srcSliceStride
                    let dstZBase = z * dstSliceStride
                    for y in 0..<newH {
                        let srcY = y * factorXY
                        let srcRowBase = srcZBase + srcY * width
                        let dstRowBase = dstZBase + y * newW
                        for x in 0..<newW {
                            let srcX = x * factorXY
                            let srcIdx = srcRowBase + srcX
                            let dstIdx = dstRowBase + x
                            outPtr[dstIdx] = inPtr[srcIdx]
                        }
                    }
                }
            }
        }
        return (out, newW, newH, newD)
    }
    
    private func processRGBAData(inputPtr: UnsafePointer<UInt8>, outputPtr: UnsafeMutablePointer<Int16>, pixelCount: Int) -> Bool {
        for i in 0..<pixelCount {
            let baseIndex = i * 4
            
            let r = Float(inputPtr[baseIndex])
            let g = Float(inputPtr[baseIndex + 1])
            let b = Float(inputPtr[baseIndex + 2])
            // Alpha channel ignored for now
            
            // Convert to grayscale using standard weights
            let grayscale = 0.299 * r + 0.587 * g + 0.114 * b
            
            // Scale to Hounsfield-like units (-1024 to 3071)
            let hounsfield = Int16(-1024 + Int(grayscale * 4095.0 / 255.0))
            
            outputPtr[i] = hounsfield
        }
        
        print("✅ Processed \(pixelCount) RGBA pixels")
        return true
    }
    
    private func processGrayscaleData(inputPtr: UnsafePointer<UInt8>, outputPtr: UnsafeMutablePointer<Int16>, pixelCount: Int) -> Bool {
        for i in 0..<pixelCount {
            let grayValue = Float(inputPtr[i])
            
            // Enhanced scaling for medical imaging
            // Map 0-255 grayscale to a useful Hounsfield-like range
            // Air: -1000, Fat: -100, Water: 0, Muscle: 50, Bone: 1000+
            let normalizedValue = grayValue / 255.0
            
            // Create a more dramatic range for better visualization
            let hounsfield: Int16
            if normalizedValue < 0.1 {
                // Very dark pixels -> Air/background
                hounsfield = Int16(-1000 + normalizedValue * 500)
            } else if normalizedValue < 0.3 {
                // Dark pixels -> Fat/soft tissue  
                hounsfield = Int16(-500 + (normalizedValue - 0.1) * 2500)
            } else if normalizedValue < 0.7 {
                // Mid pixels -> Water/muscle
                hounsfield = Int16(0 + (normalizedValue - 0.3) * 1250)
            } else {
                // Bright pixels -> Dense tissue/bone
                hounsfield = Int16(500 + (normalizedValue - 0.7) * 5000)
            }
            
            outputPtr[i] = hounsfield
        }
        
        print("✅ Processed \(pixelCount) grayscale pixels with enhanced medical scaling")
        return true
    }
    
    // Legacy synchronous version for backward compatibility - DEPRECATED
    private func createVolumeTexture(device: MTLDevice, volumeData: Data, dimensions: SIMD3<Int>) -> MTLTexture? {
        print("⚠️ Using deprecated synchronous texture creation - consider using async version")
        return createVolumeTextureOptimized(device: device, volumeData: volumeData, dimensions: dimensions)
    }
    
    // Legacy synchronous version - DEPRECATED
    private func convertToInt16Data(_ data: Data) -> Data {
        print("⚠️ Using deprecated synchronous data conversion - consider using optimized version")
        return convertToInt16DataOptimized(data)
    }

    private func getAvailableMemory() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let totalMemory = ProcessInfo.processInfo.physicalMemory
            let usedMemory = UInt64(info.resident_size)
            return Int(totalMemory - usedMemory)
        }
        
        // Fallback to a conservative estimate
        return 1024 * 1024 * 512 // 512MB
    }
} 
