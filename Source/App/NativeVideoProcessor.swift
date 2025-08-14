import AVFoundation
import AppKit
import UniformTypeIdentifiers

public class NativeVideoProcessor {
    
    public enum ProcessorError: Error {
        case assetInitializationFailed
        case frameExtractionFailed(Error)
    }
    
    private var completion: ((Result<Void, ProcessorError>) -> Void)?

    public init() {}

    /// Processes a video file by synchronously extracting frames on a background thread.
    public func processVideo(
        _ url: URL,
        to outputDir: URL,
        frameInterval: Double = 1.0 / 30.0, // Default to 30 FPS
        completion: @escaping (Result<Void, ProcessorError>) -> Void
    ) {
        self.completion = completion
        // Perform all work on a background thread to keep the UI responsive.
        DispatchQueue.global(qos: .userInitiated).async {
            print("[VideoProcessor] Starting processing for URL: \(url.path)")
            let asset = AVURLAsset(url: url)

            guard asset.isPlayable, let videoTrack = asset.tracks(withMediaType: .video).first else {
                self.complete(with: .failure(.assetInitializationFailed))
                return
            }
            
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero

            let videoDuration = videoTrack.timeRange.duration.seconds
            let times = stride(from: 0, to: videoDuration, by: frameInterval).map {
                CMTime(seconds: $0, preferredTimescale: 600)
            }
            
            guard !times.isEmpty else {
                print("[VideoProcessor] Error: No frames to generate.")
                self.complete(with: .failure(.assetInitializationFailed))
                return
            }

            print("[VideoProcessor] Will attempt to generate \(times.count) frames.")
            let startTime = Date()
            
            do {
                var savedFrameCount = 0
                for (index, time) in times.enumerated() {
                    let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                    if self.save(image: cgImage, to: outputDir, frameCount: index) {
                        savedFrameCount += 1
                    }
                }
                let duration = Date().timeIntervalSince(startTime)
                print("✅ [VideoProcessor] Finished successfully in \(String(format: "%.2f", duration))s. Saved \(savedFrameCount) frames.")
                self.complete(with: .success(()))
                
            } catch {
                print("❌ [VideoProcessor] Failed during frame extraction. Error: \(error.localizedDescription)")
                self.complete(with: .failure(.frameExtractionFailed(error)))
            }
        }
    }
    
    /// Helper to dispatch completion back to the main thread.
    private func complete(with result: Result<Void, ProcessorError>) {
        DispatchQueue.main.async {
            self.completion?(result)
            self.completion = nil // Avoid retaining cycles
        }
    }
    
    /// Converts a CGImage to grayscale and saves it to a PNG file.
    private func save(image: CGImage, to outputDir: URL, frameCount: Int) -> Bool {
        guard let grayscaleImage = self.convertToGrayscale(image: image) else {
            print("⚠️ Warning: Could not convert frame \(frameCount) to grayscale.")
            return false
        }

        let fileName = String(format: "frame_%04d.png", frameCount)
        let outputURL = outputDir.appendingPathComponent(fileName)

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, grayscaleImage, nil)
        
        return CGImageDestinationFinalize(destination)
    }

    /// Converts a CGImage to a single-channel grayscale image.
    private func convertToGrayscale(image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: rect)
        
        return context.makeImage()
    }
} 