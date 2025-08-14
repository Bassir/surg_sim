import SwiftUI
import SceneKit
import Metal
import Foundation
import UniformTypeIdentifiers
import simd

// UserDefaults key for recent files
private let kRecentFilesKey = "RecentVideoFiles"

// The main view of the application - single window approach
struct ContentView: View {
    @State private var selectedVideoURL: URL?
    @State private var showAlert = false
    @State private var errorMessage = ""
    @State private var processingStatus = ""
    @State private var volumeOutputPath: String?
    @State private var recentFiles: [URL] = []
    @State private var isDragOver = false
    
    // 3D rendering state
    @State private var isVolumeLoaded = false
    @State private var volumeData: Data = Data()
    @State private var dimensions: SIMD3<Int> = .zero
    @State private var volumeCube = SCNNode()
    @State private var transferFunction = SimpleTransferFunction()

    // MARK: - Volume state extensions
    @State private var currentSliceIndex: Int = 0
    @State private var maxSliceIndex: Int = 0
    @State private var originalFrames: [NSImage] = [] // Store original frames for slice viewing
    @State private var showSliceOverlay: Bool = true
    @State private var sliceClippingEnabled: Bool = false

    var body: some View {
        HSplitView {
            // Left Side: Controls
            VStack(spacing: 20) {
                Text("Surgical Planner")
                    .font(.title)
                    .fontWeight(.bold)

                if !isVolumeLoaded {
                    // File selection area
                    fileSelectionArea
                    
                    if !recentFiles.isEmpty {
                        recentFilesSection
                    }
                    
                    if !processingStatus.isEmpty {
                        processingStatusView
                    }
                } else {
                    // Enhanced volume controls with slice navigation
                    volumeControlsPanel
                }
                
                Spacer()
            }
            .frame(minWidth: 320, maxWidth: 450)
            .padding()
            
            // Right Side: Multi-panel viewer
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(isVolumeLoaded ? "Hybrid Volume Viewer" : "Drop Video to Begin")
                        .font(.headline)
                    Spacer()
                    if isVolumeLoaded {
                        HStack(spacing: 12) {
                            Button(showSliceOverlay ? "Hide Slice" : "Show Slice") {
                                showSliceOverlay.toggle()
                                updateVolumeRendering()
                            }
                            .buttonStyle(.bordered)
                            
                            Button(sliceClippingEnabled ? "Disable Clipping" : "Enable Clipping") {
                                sliceClippingEnabled.toggle()
                                updateVolumeRendering()
                            }
                            .buttonStyle(.bordered)
                            
                        Button("Reset") {
                            resetToFileSelection()
                        }
                        .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                
                // Multi-panel viewer
                if isVolumeLoaded {
                    revolutionaryViewerInterface
                } else {
                    dropZoneView
                }
            }
        }
        .frame(minWidth: 1200, minHeight: 700)
        .onAppear {
            loadRecentFiles()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    // MARK: - File Selection Components
    
    private var fileSelectionArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                .foregroundColor(isDragOver ? Color.blue : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDragOver ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
                )
            
            VStack(spacing: 16) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(isDragOver ? .blue : .secondary)
                
                if let url = selectedVideoURL {
                    VStack(spacing: 4) {
                        Text("Selected:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(url.lastPathComponent)
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("Drag Video Here")
                            .font(.headline)
                        Text("or click to browse")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if selectedVideoURL != nil {
                    Button("Process Video") {
                        processSelectedVideo()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(processingStatus.isEmpty == false)
                }
            }
            .padding()
        }
        .frame(height: 140)
        .onTapGesture {
            if selectedVideoURL == nil {
                selectVideoFile()
            }
        }
        .onDrop(of: [.movie, .video], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private var recentFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Files")
                .font(.subheadline)
            
            VStack(spacing: 4) {
                ForEach(Array(recentFiles.prefix(3).enumerated()), id: \.offset) { index, url in
                    Button(action: {
                        selectedVideoURL = url
                    }) {
                        HStack {
                            Image(systemName: "video.fill")
                                .foregroundColor(.blue)
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedVideoURL == url ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var processingStatusView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text(processingStatus)
                .font(.caption)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Revolutionary Multi-Panel Interface

    private var revolutionaryViewerInterface: some View {
        GeometryReader { geometry in
            VStack(spacing: 1) {
                // Top row: Axial (left) and 3D Volume (right)
                HStack(spacing: 1) {
                    // Axial slice view (ground truth)
                    VStack(spacing: 0) {
                        Text("Axial (Ground Truth)")
                            .font(.caption)
                            .padding(4)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                        
                        axialSliceView
                            .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.5)
                    }
                    
                    // 3D Volume rendering with clipping
                    VStack(spacing: 0) {
                        Text("3D Volume + Clipping")
                            .font(.caption)
                            .padding(4)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                        
                        Enhanced3DVolumeView(volumeCube: volumeCube, 
                                           transferFunction: $transferFunction,
                                           currentSlice: $currentSliceIndex,
                                           maxSlice: maxSliceIndex,
                                           showSliceOverlay: showSliceOverlay,
                                           clippingEnabled: sliceClippingEnabled)
                            .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.5)
                    }
                }
                
                // Bottom row: Sagittal (left) and Coronal (right)
                HStack(spacing: 1) {
                    // Sagittal view (YZ plane)
                    VStack(spacing: 0) {
                        Text("Sagittal (YZ)")
                            .font(.caption)
                            .padding(4)
                            .frame(maxWidth: .infinity)
                            .background(Color.green.opacity(0.1))
                        
                        sagittalSliceView
                            .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.5)
                    }
                    
                    // Coronal view (XZ plane)
                    VStack(spacing: 0) {
                        Text("Coronal (XZ)")
                            .font(.caption)
                            .padding(4)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                        
                        coronalSliceView
                            .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.5)
                    }
                }
            }
        }
    }

    // MARK: - Slice Views

    private var axialSliceView: some View {
        ZStack {
            Color.black
            
            if currentSliceIndex < originalFrames.count {
                Image(nsImage: originalFrames[currentSliceIndex])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay(
                        // Crosshair overlay
                        Path { path in
                            let center = CGPoint(x: 50, y: 50) // This would be calculated from mouse position
                            path.move(to: CGPoint(x: center.x - 10, y: center.y))
                            path.addLine(to: CGPoint(x: center.x + 10, y: center.y))
                            path.move(to: CGPoint(x: center.x, y: center.y - 10))
                            path.addLine(to: CGPoint(x: center.x, y: center.y + 10))
                        }
                        .stroke(Color.cyan, lineWidth: 1)
                    )
            } else {
                Text("Slice \(currentSliceIndex + 1)")
                    .foregroundColor(.white)
            }
        }
        .overlay(
            VStack {
                Spacer()
                HStack {
                    Text("Slice: \(currentSliceIndex + 1)/\(maxSliceIndex + 1)")
                        .font(.caption)
                        .padding(4)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(8)
            }
        )
    }

    private var sagittalSliceView: some View {
        ZStack {
            Color.black
            
            // Generate sagittal slice from volume data
            if let sagittalImage = generateSagittalSlice() {
                Image(nsImage: sagittalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("Sagittal View")
                    .foregroundColor(.white)
            }
        }
        .overlay(
            VStack {
                Spacer()
                HStack {
                    Text("Y-Z Plane")
                        .font(.caption)
                        .padding(4)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(8)
            }
        )
    }

    private var coronalSliceView: some View {
        ZStack {
            Color.black
            
            // Generate coronal slice from volume data
            if let coronalImage = generateCoronalSlice() {
                Image(nsImage: coronalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("Coronal View")
                    .foregroundColor(.white)
            }
        }
        .overlay(
            VStack {
                Spacer()
                HStack {
                    Text("X-Z Plane")
                        .font(.caption)
                        .padding(4)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(8)
            }
        )
    }

    // MARK: - Enhanced Volume Controls

    private var volumeControlsPanel: some View {
        VStack(spacing: 20) {
            Text("Volume Controls")
                .font(.headline)
            
            // Slice Navigation
            VStack(alignment: .leading, spacing: 8) {
                Text("Slice Navigation")
                    .font(.subheadline)
                
                HStack {
                    Button("⏮") {
                        currentSliceIndex = 0
                        updateVolumeRendering()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("◀") {
                        if currentSliceIndex > 0 {
                            currentSliceIndex -= 1
                            updateVolumeRendering()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Text("\(currentSliceIndex + 1)")
                        .font(.caption)
                        .frame(width: 40)
                    
                    Button("▶") {
                        if currentSliceIndex < maxSliceIndex {
                            currentSliceIndex += 1
                            updateVolumeRendering()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("⏭") {
                        currentSliceIndex = maxSliceIndex
                        updateVolumeRendering()
                    }
                    .buttonStyle(.bordered)
                }
                
                Slider(value: Binding(
                    get: { Double(currentSliceIndex) },
                    set: { currentSliceIndex = Int($0) }
                ), in: 0...Double(maxSliceIndex), step: 1) {
                    Text("Slice")
                }
                .onChange(of: currentSliceIndex) { _ in
                    updateVolumeRendering()
                }
            }
            .padding()
            .background(Color.purple.opacity(0.1))
            .cornerRadius(8)
            
            // Transfer Function Controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Transfer Function")
                    .font(.subheadline)
                
                HStack {
                    Text("\(Int(transferFunction.threshold))")
                        .font(.caption)
                        .frame(width: 40)
                    
                    Slider(value: $transferFunction.threshold, in: -1000...3000) {
                        Text("Threshold")
                    }
                    .onChange(of: transferFunction.threshold) { _ in
                        updateVolumeRendering()
                    }
                    
                    Text("3000")
                        .font(.caption)
                        .frame(width: 40)
                }
                
                HStack {
                    Text("0%")
                        .font(.caption)
                        .frame(width: 30)
                    
                    Slider(value: $transferFunction.opacity, in: 0...1) {
                        Text("Opacity")
                    }
                    .onChange(of: transferFunction.opacity) { _ in
                        updateVolumeRendering()
                    }
                    
                    Text("100%")
                        .font(.caption)
                        .frame(width: 30)
                }
                
                Text("Opacity: \(Int(transferFunction.opacity * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // Window/Level Controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Window/Level (Medical Imaging)")
                    .font(.subheadline)
                
                HStack {
                    Text("Window: \(Int(transferFunction.window))")
                        .font(.caption)
                        .frame(width: 80)
                    
                    Slider(value: $transferFunction.window, in: 50...4000) {
                        Text("Window Width")
                    }
                    .onChange(of: transferFunction.window) { _ in
                        updateWindowLevel()
                    }
                }
                
                HStack {
                    Text("Level: \(Int(transferFunction.level))")
                        .font(.caption)
                        .frame(width: 80)
                    
                    Slider(value: $transferFunction.level, in: -1000...2000) {
                        Text("Window Level")
                    }
                    .onChange(of: transferFunction.level) { _ in
                        updateWindowLevel()
                    }
                }
                
                // Preset window/level settings
                HStack(spacing: 4) {
                    Button("Soft Tissue") {
                        transferFunction.window = 350
                        transferFunction.level = 40
                        updateWindowLevel()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    
                    Button("Bone") {
                        transferFunction.window = 1500
                        transferFunction.level = 300
                        updateWindowLevel()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    
                    Button("Brain") {
                        transferFunction.window = 80
                        transferFunction.level = 40
                        updateWindowLevel()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            
            // Colormap Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Colormap")
                    .font(.subheadline)
                
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Button("Grayscale") {
                            transferFunction.selectedColormap = .grayscale
                            updateVolumeRendering()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .background(transferFunction.selectedColormap == .grayscale ? Color.green.opacity(0.2) : Color.clear)
                        
                        Button("Bone") {
                            transferFunction.selectedColormap = .bone
                            updateVolumeRendering()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .background(transferFunction.selectedColormap == .bone ? Color.green.opacity(0.2) : Color.clear)
                        
                        Button("Hot") {
                            transferFunction.selectedColormap = .hot
                            updateVolumeRendering()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .background(transferFunction.selectedColormap == .hot ? Color.green.opacity(0.2) : Color.clear)
                    }
                    
                    HStack(spacing: 4) {
                        Button("Cool") {
                            transferFunction.selectedColormap = .cool
                            updateVolumeRendering()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .background(transferFunction.selectedColormap == .cool ? Color.green.opacity(0.2) : Color.clear)
                        
                        Button("Viridis") {
                            transferFunction.selectedColormap = .viridis
                            updateVolumeRendering()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .background(transferFunction.selectedColormap == .viridis ? Color.green.opacity(0.2) : Color.clear)
                        
                        Button("Plasma") {
                            transferFunction.selectedColormap = .plasma
                            updateVolumeRendering()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .background(transferFunction.selectedColormap == .plasma ? Color.green.opacity(0.2) : Color.clear)
                    }
                }
                
                Text("Selected: \(transferFunction.selectedColormap.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
            
            // Paint Tool
            VStack(alignment: .leading, spacing: 8) {
                Text("Surgical Tools")
                    .font(.subheadline)
                
                HStack {
                    Text("Size: \(Int(transferFunction.brushSize))")
                        .font(.caption)
                        .frame(width: 60)
                    
                    Slider(value: $transferFunction.brushSize, in: 5...50) {
                        Text("Brush Size")
                    }
                }
                
                // Surgical Tool Selection
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tool: \(transferFunction.selectedTool.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        Button(toolIcon(for: .scalpel)) {
                            transferFunction.selectTool(.scalpel)
                            updateVolumeRendering()
                        }
                        .buttonStyle(.bordered)
                        .background(transferFunction.selectedTool == .scalpel ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                        
                        Button(toolIcon(for: .drill)) {
                            transferFunction.selectTool(.drill)
                            updateVolumeRendering()
                        }
                        .buttonStyle(.bordered)
                        .background(transferFunction.selectedTool == .drill ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                        
                        Button(toolIcon(for: .bone)) {
                            transferFunction.selectTool(.bone)
                            updateVolumeRendering()
                        }
                        .buttonStyle(.bordered)
                        .background(transferFunction.selectedTool == .bone ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                        
                        Button(toolIcon(for: .softtissue)) {
                            transferFunction.selectTool(.softtissue)
                            updateVolumeRendering()
                        }
                        .buttonStyle(.bordered)
                        .background(transferFunction.selectedTool == .softtissue ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                    }
                }
                
                // Paint Actions
                HStack(spacing: 8) {
                    Button("🖌 Paint Mode") {
                        transferFunction.isPaintMode = true
                        transferFunction.isEraseMode = false
                        if transferFunction.selectedTool == .none {
                            transferFunction.selectedTool = .scalpel
                        }
                        updateVolumeRendering()
                    }
                    .buttonStyle(.borderedProminent)
                    .background(transferFunction.isPaintMode ? Color.blue.opacity(0.3) : Color.clear)
                    
                    Button("🗑 Erase Mode") {
                        transferFunction.isEraseMode = true
                        transferFunction.isPaintMode = false
                        updateVolumeRendering()
                    }
                    .buttonStyle(.bordered)
                    .background(transferFunction.isEraseMode ? Color.red.opacity(0.3) : Color.clear)
                    
                    Button("🔄 Clear All") {
                        transferFunction.clearPaint()
                        updatePaintMask()
                        updateVolumeRendering()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color.green.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Drop Zone
    
    private var dropZoneView: some View {
        ZStack {
            Color.black.opacity(0.8)
            
            VStack(spacing: 20) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                
                Text("Volume Viewer")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Select a video file to view 3D volume")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onDrop(of: [.movie, .video], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }
    
    // MARK: - File Handling
    
    private func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi]
        panel.title = "Select Video File"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                selectedVideoURL = url
                addToRecentFiles(url)
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
               provider.hasItemConformingToTypeIdentifier(UTType.video.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { item, error in
                    DispatchQueue.main.async {
                        if let url = item as? URL {
                            selectedVideoURL = url
                            addToRecentFiles(url)
                        }
                    }
                }
                return true
            }
        }
        return false
    }
    
    private func loadRecentFiles() {
        if let data = UserDefaults.standard.data(forKey: kRecentFilesKey),
           let urls = try? JSONDecoder().decode([URL].self, from: data) {
            recentFiles = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }
    
    private func addToRecentFiles(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        recentFiles = Array(recentFiles.prefix(5))
        
        if let data = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(data, forKey: kRecentFilesKey)
        }
    }
    
    private func processSelectedVideo() {
        guard let url = selectedVideoURL else { return }
        
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            
            processingStatus = "Processing video frames..."
            
            DispatchQueue.global(qos: .userInitiated).async {
                let processor = NativeVideoProcessor()
                processor.processVideo(url, to: outputDir) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.loadVolumeData(from: outputDir.path)
                            processingStatus = ""
                        case .failure(let error):
                            errorMessage = "Failed to process video: \(error.localizedDescription)"
                            showAlert = true
                            processingStatus = ""
                        }
                    }
                }
            }
        } catch {
            errorMessage = "Could not create temporary directory: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func loadVolumeData(from directoryPath: String) {
        if let (data, dims) = loadVolumeDataFromDirectory(directoryPath) {
            self.volumeData = data
            self.dimensions = dims
            self.isVolumeLoaded = true
            setupVolumeRendering()
        } else {
            errorMessage = "Failed to load volume data"
            showAlert = true
        }
    }
    
    private func resetToFileSelection() {
        isVolumeLoaded = false
        volumeData = Data()
        dimensions = .zero
        selectedVideoURL = nil
        transferFunction = SimpleTransferFunction()
        currentSliceIndex = 0
        maxSliceIndex = 0
        originalFrames.removeAll()
        showSliceOverlay = true
        sliceClippingEnabled = false
    }
    
    // MARK: - Orthogonal Slice Generation
    
    private func generateSagittalSlice() -> NSImage? {
        guard !volumeData.isEmpty && dimensions.x > 0 && dimensions.y > 0 && dimensions.z > 0 else {
            return nil
        }
        
        let sliceX = Int(Float(currentSliceIndex) / Float(maxSliceIndex) * Float(dimensions.x))
        let width = dimensions.y
        let height = dimensions.z
        
        // Create sagittal slice data (YZ plane at position X)
        var sliceData = Data(count: width * height)
        
        sliceData.withUnsafeMutableBytes { bytes in
            guard let ptr = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            
            for z in 0..<height {
                for y in 0..<width {
                    let volumeIndex = z * dimensions.x * dimensions.y + y * dimensions.x + sliceX
                    if volumeIndex < volumeData.count {
                        ptr[z * width + y] = volumeData[volumeIndex]
                    }
                }
            }
        }
        
        return createImageFromData(sliceData, width: width, height: height)
    }
    
    private func generateCoronalSlice() -> NSImage? {
        guard !volumeData.isEmpty && dimensions.x > 0 && dimensions.y > 0 && dimensions.z > 0 else {
            return nil
        }
        
        let sliceY = Int(Float(currentSliceIndex) / Float(maxSliceIndex) * Float(dimensions.y))
        let width = dimensions.x
        let height = dimensions.z
        
        // Create coronal slice data (XZ plane at position Y)
        var sliceData = Data(count: width * height)
        
        sliceData.withUnsafeMutableBytes { bytes in
            guard let ptr = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            
            for z in 0..<height {
                for x in 0..<width {
                    let volumeIndex = z * dimensions.x * dimensions.y + sliceY * dimensions.x + x
                    if volumeIndex < volumeData.count {
                        ptr[z * width + x] = volumeData[volumeIndex]
                    }
                }
            }
        }
        
        return createImageFromData(sliceData, width: width, height: height)
    }
    
    private func createImageFromData(_ data: Data, width: Int, height: Int) -> NSImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let context = CGContext(
            data: UnsafeMutablePointer(mutating: data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress }),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
    
    // MARK: - Volume Loading with Frame Storage
    
    private func loadVolumeDataFromDirectory(_ directoryPath: String) -> (Data, SIMD3<Int>)? {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: directoryPath).sorted() else {
            print("❌ Failed to read directory: \(directoryPath)")
            return nil
        }

        var volumeData = Data()
        var width = 0
        var height = 0
        var validFrameCount = 0

        print("📁 Loading \(files.count) files from directory...")

        // Pre-allocate space for better performance
        var frameDataArray: [Data] = []
        originalFrames.removeAll() // Clear previous frames

        for (index, fileName) in files.enumerated() {
            let filePath = (directoryPath as NSString).appendingPathComponent(fileName)
            guard let image = NSImage(contentsOfFile: filePath),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("⚠️ Skipping invalid image: \(fileName)")
                continue
            }
            
            if index == 0 {
                width = cgImage.width
                height = cgImage.height
                print("📏 Frame dimensions: \(width)x\(height)")
            }

            // Store original frame for slice viewing
            originalFrames.append(image)

            // Convert each frame to grayscale for proper volume stacking
            guard let grayscaleData = convertFrameToGrayscale(cgImage: cgImage, width: width, height: height) else {
                print("⚠️ Failed to convert frame to grayscale: \(fileName)")
                continue
            }
            
            frameDataArray.append(grayscaleData)
            validFrameCount += 1
            
            if validFrameCount % 10 == 0 {
                print("📊 Loaded \(validFrameCount) frames...")
            }
        }
        
        guard !frameDataArray.isEmpty, width > 0, height > 0, validFrameCount > 0 else {
            print("❌ No valid frame data loaded")
            return nil
        }
        
        // Set slice navigation bounds
        maxSliceIndex = validFrameCount - 1
        currentSliceIndex = maxSliceIndex / 2 // Start at middle slice
        
        // Create properly ordered 3D volume data
        print("🔄 Creating 3D volume texture from \(validFrameCount) frames...")
        volumeData = create3DVolumeData(frames: frameDataArray, width: width, height: height, depth: validFrameCount)
        
        let depth = validFrameCount
        
        print("✅ Volume data created:")
        print("   📐 Dimensions: \(width)x\(height)x\(depth)")
        print("   💾 Total data: \(volumeData.count) bytes")
        print("   🧮 Bytes per slice: \(volumeData.count / validFrameCount)")
        print("   📊 Original frames stored: \(originalFrames.count)")
        
        return (volumeData, SIMD3<Int>(width, height, depth))
    }
    
    private func convertFrameToGrayscale(cgImage: CGImage, width: Int, height: Int) -> Data? {
        // Create a grayscale context
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
        
        // Draw the image into the grayscale context
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(cgImage, in: rect)
        
        // Get the grayscale data
        guard let data = context.data else { return nil }
        return Data(bytes: data, count: width * height)
    }
    
    private func create3DVolumeData(frames: [Data], width: Int, height: Int, depth: Int) -> Data {
        var volumeData = Data(capacity: width * height * depth)
        
        // Stack frames in the correct order for 3D texture
        for frameData in frames {
            volumeData.append(frameData)
        }
        
        print("🏗️ Created 3D volume: \(width)x\(height)x\(depth) = \(volumeData.count) bytes")
        return volumeData
    }
    
    // MARK: - Volume Rendering
    
    private func setupVolumeRendering() {
        volumeCube.name = "volumeCube"
        volumeCube.geometry = SCNBox(width: 1.0, height: 1.0, length: 1.0, chamferRadius: 0.0)
        
        print("🏗️ Setting up volume rendering...")
        print("📊 Volume data size: \(volumeData.count) bytes")
        print("📐 Volume dimensions: \(dimensions)")
        
        guard let device = MTLCreateSystemDefaultDevice() else { 
            print("❌ Failed to create Metal device")
            errorMessage = "Failed to create Metal device"
            showAlert = true
            return 
        }
        
        print("✅ Metal device created successfully")
        
        // Validate volume data before proceeding
        guard !volumeData.isEmpty else {
            print("❌ Volume data is empty")
            errorMessage = "Volume data is empty"
            showAlert = true
            return
        }
        
        guard dimensions.x > 0 && dimensions.y > 0 && dimensions.z > 0 else {
            print("❌ Invalid dimensions: \(dimensions)")
            errorMessage = "Invalid volume dimensions: \(dimensions)"
            showAlert = true
            return
        }
        
        // Create VolumeCubeMaterial with optimized async approach
        let volumeMaterial = VolumeCubeMaterial(device: device)
        print("✅ VolumeCubeMaterial created")
        
        // Use async version to prevent blocking the main thread
        processingStatus = "Converting volume data..."
        print("🔄 Starting volume data conversion...")
        
        volumeMaterial.setVolumeData(device: device, volumeData: volumeData, dimensions: dimensions) { success in
            DispatchQueue.main.async {
                if success {
                    self.volumeCube.geometry?.materials = [volumeMaterial]
                    self.processingStatus = ""
                    print("✅ Volume rendering setup complete")
                    print("🎭 Material assigned to cube geometry")
                } else {
                    self.processingStatus = ""
                    print("❌ Volume data conversion failed")
                    self.errorMessage = "Failed to setup volume rendering - check console for details"
                    self.showAlert = true
                }
            }
        }
    }
    
    private func updateVolumeRendering() {
        guard let geometry = volumeCube.geometry,
              let material = geometry.materials.first as? VolumeCubeMaterial else { 
            print("❌ No geometry or VolumeCubeMaterial found")
            return 
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else { 
            print("❌ Failed to create Metal device for transfer function update")
            return 
        }
        
        print("🔄 Updating volume rendering - threshold: \(transferFunction.threshold), opacity: \(transferFunction.opacity)")
        
        // Use the proper dynamic transfer function update method
        material.updateDynamicTransferFunction(device: device, threshold: transferFunction.threshold, opacity: transferFunction.opacity)
        
        // Debug: Print current slider values
        print("🎛️ Current settings:")
        print("   Threshold: \(transferFunction.threshold)")
        print("   Opacity: \(transferFunction.opacity)")
        print("   Brush Size: \(transferFunction.brushSize)")
        
        print("✅ Volume rendering update complete")
    }
    
    // MARK: - Surgical Tools Helper Functions
    
    private func toolIcon(for tool: SimpleTransferFunction.SurgicalTool) -> String {
        switch tool {
        case .none: return "hand.point.up"
        case .scalpel: return "🔪"
        case .drill: return "⚙️"
        case .bone: return "🦴"
        case .softtissue: return "🫀"
        }
    }
    
    private func updatePaintMask() {
        guard let geometry = volumeCube.geometry,
              let material = geometry.materials.first as? VolumeCubeMaterial else {
            print("❌ No geometry or VolumeCubeMaterial found for paint mask update")
            return
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Failed to create Metal device for paint mask update")
            return
        }
        
        // Clear or update paint mask
        if transferFunction.paintMask.isEmpty {
            material.clearPaintMask(device: device, dimensions: dimensions)
        } else {
            material.updatePaintMask(device: device, paintData: transferFunction.paintMask, dimensions: dimensions)
        }
        
        print("✅ Paint mask updated")
    }
    
    private func updateWindowLevel() {
        guard let geometry = volumeCube.geometry,
              let material = geometry.materials.first as? VolumeCubeMaterial else {
            print("❌ No geometry or VolumeCubeMaterial found for window/level update")
            return
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Failed to create Metal device for window/level update")
            return
        }
        
        // Convert window/level to threshold and opacity for the volume rendering
        let adjustedThreshold = transferFunction.level
        let normalizedOpacity = transferFunction.opacity
        
        // Update the voxel range based on window/level
        material.setVoxelRange(min: Int32(transferFunction.windowMin), max: Int32(transferFunction.windowMax))
        
        // Update the dynamic transfer function
        material.updateDynamicTransferFunction(device: device, threshold: adjustedThreshold, opacity: normalizedOpacity)
        
        print("🔧 Window/Level updated: Window=\(transferFunction.window), Level=\(transferFunction.level)")
        print("   Range: \(transferFunction.windowMin) to \(transferFunction.windowMax)")
    }
}

// MARK: - Enhanced Transfer Function with Surgical Tools

struct SimpleTransferFunction {
    var threshold: Float = 0
    var opacity: Float = 0.5
    var brushSize: Float = 10
    var paintMask: Data = Data()
    var isPaintMode: Bool = false
    var isEraseMode: Bool = false
    var selectedTool: SurgicalTool = .none
    
    // Window/Level controls
    var window: Float = 1000  // Window width
    var level: Float = 0      // Window level (center)
    
    // Colormap selection
    var selectedColormap: Colormap = .grayscale
    
    // Surgical tool types
    enum SurgicalTool: CaseIterable, Hashable {
        case none, scalpel, drill, bone, softtissue
        
        var name: String {
            switch self {
            case .none: return "Select"
            case .scalpel: return "Scalpel"
            case .drill: return "Drill"
            case .bone: return "Bone Tool"
            case .softtissue: return "Soft Tissue"
            }
        }
        
        var threshold: Float {
            switch self {
            case .none: return 0
            case .scalpel: return -100 // Cuts through soft tissue
            case .drill: return 800    // Cuts through bone
            case .bone: return 600     // Bone specific
            case .softtissue: return 50 // Soft tissue specific
            }
        }
    }
    
    // Colormap types for different tissue visualization
    enum Colormap: CaseIterable, Hashable {
        case grayscale, bone, hot, cool, viridis, plasma
        
        var name: String {
            switch self {
            case .grayscale: return "Grayscale"
            case .bone: return "Bone"
            case .hot: return "Hot"
            case .cool: return "Cool"
            case .viridis: return "Viridis"
            case .plasma: return "Plasma"
            }
        }
    }
    
    mutating func clearPaint() {
        paintMask = Data()
    }
    
    mutating func selectTool(_ tool: SurgicalTool) {
        selectedTool = tool
        threshold = tool.threshold
        isPaintMode = tool != .none
        isEraseMode = false
    }
    
    // Convert window/level to threshold values
    var windowMin: Float {
        return level - (window / 2)
    }
    
    var windowMax: Float {
        return level + (window / 2)
    }
}

// MARK: - SceneKit View

struct VolumeSceneView: NSViewRepresentable {
    var volumeCube: SCNNode
    @Binding var transferFunction: SimpleTransferFunction

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        let scene = SCNScene()
        scnView.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 2)
        scene.rootNode.addChildNode(cameraNode)

        scnView.allowsCameraControl = true
        scnView.backgroundColor = NSColor.black

        scene.rootNode.addChildNode(volumeCube)
        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        // Transfer function updates are handled by the parent view
    }
}

// MARK: - Enhanced 3D Volume View with Clipping and Paint Tools

struct Enhanced3DVolumeView: NSViewRepresentable {
    var volumeCube: SCNNode
    @Binding var transferFunction: SimpleTransferFunction
    @Binding var currentSlice: Int
    var maxSlice: Int
    var showSliceOverlay: Bool
    var clippingEnabled: Bool

    func makeNSView(context: Context) -> SCNView {
        let scnView = PaintableSCNView()
        setupScene(for: scnView)
        return scnView
    }
    
    private func setupScene(for scnView: PaintableSCNView) {
        let scene = SCNScene()
        scnView.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 2)
        scene.rootNode.addChildNode(cameraNode)

        scnView.allowsCameraControl = true
        scnView.backgroundColor = NSColor.black
        
        // Set up paint functionality
        scnView.transferFunction = transferFunction
        scnView.onPaintAction = handlePaintAction

        // Add slice plane overlay if enabled
        if showSliceOverlay {
            let slicePlane = createSlicePlane()
            scene.rootNode.addChildNode(slicePlane)
        }

        // Apply clipping if enabled
        if clippingEnabled {
            let clippingPlane = createClippingPlane()
            scene.rootNode.addChildNode(clippingPlane)
        }

        scene.rootNode.addChildNode(volumeCube)
    }
    
    private func handlePaintAction(location: CGPoint) {
        print("🎨 Paint action at: \(location)")
        // Simplified paint handling for now
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        // Simplified update method
        updatePaintableView(nsView)
        updateSceneElements(nsView)
    }
    
    private func updatePaintableView(_ nsView: SCNView) {
        if let paintableView = nsView as? PaintableSCNView {
            paintableView.transferFunction = transferFunction
        }
    }
    
    private func updateSceneElements(_ nsView: SCNView) {
        guard let scene = nsView.scene else { return }
        
        if showSliceOverlay {
            updateSlicePlane(in: scene)
        }
        
        if clippingEnabled {
            updateClippingPlane(in: scene)
        }
    }
    
    private func createSlicePlane() -> SCNNode {
        let planeGeometry = SCNPlane(width: 1.0, height: 1.0)
        let planeMaterial = SCNMaterial()
        planeMaterial.diffuse.contents = NSColor.cyan.withAlphaComponent(0.2)
        planeMaterial.transparency = 0.8
        planeMaterial.isDoubleSided = true
        planeGeometry.materials = [planeMaterial]
        
        let planeNode = SCNNode(geometry: planeGeometry)
        planeNode.name = "slicePlane"
        
        // Position based on current slice
        let sliceRatio: Float = maxSlice > 0 ? Float(currentSlice) / Float(maxSlice) : 0.5
        planeNode.position = SCNVector3(0, 0, sliceRatio - 0.5)
        
        return planeNode
    }
    
    private func createClippingPlane() -> SCNNode {
        // Create a clipping plane that cuts through the volume
        let clipGeometry = SCNPlane(width: 2.0, height: 2.0)
        let clipMaterial = SCNMaterial()
        clipMaterial.diffuse.contents = NSColor.red.withAlphaComponent(0.1)
        clipMaterial.transparency = 0.9
        clipGeometry.materials = [clipMaterial]
        
        let clipNode = SCNNode(geometry: clipGeometry)
        clipNode.name = "clippingPlane"
        
        // Position the clipping plane
        let sliceRatio: Float = maxSlice > 0 ? Float(currentSlice) / Float(maxSlice) : 0.5
        clipNode.position = SCNVector3(0, 0, sliceRatio - 0.5)
        clipNode.eulerAngles = SCNVector3(0, 0, 0)
        
        return clipNode
    }
    
    private func updateSlicePlane(in scene: SCNScene) {
        guard let slicePlane = scene.rootNode.childNode(withName: "slicePlane", recursively: false) else { return }
        
        let sliceRatio: Float = maxSlice > 0 ? Float(currentSlice) / Float(maxSlice) : 0.5
        slicePlane.position = SCNVector3(0, 0, sliceRatio - 0.5)
    }
    
    private func updateClippingPlane(in scene: SCNScene) {
        guard let clippingPlane = scene.rootNode.childNode(withName: "clippingPlane", recursively: false) else { return }
        
        let sliceRatio: Float = maxSlice > 0 ? Float(currentSlice) / Float(maxSlice) : 0.5
        clippingPlane.position = SCNVector3(0, 0, sliceRatio - 0.5)
    }
}

// MARK: - Paintable SCNView for Mouse Interaction

class PaintableSCNView: SCNView {
    var transferFunction: SimpleTransferFunction = SimpleTransferFunction()
    var onPaintAction: ((CGPoint) -> Void)?
    private var isDragging = false
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        
        if transferFunction.isPaintMode || transferFunction.isEraseMode {
            isDragging = true
            onPaintAction?(location)
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        
        if isDragging && (transferFunction.isPaintMode || transferFunction.isEraseMode) {
            onPaintAction?(location)
        } else {
            super.mouseDragged(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
        } else {
            super.mouseUp(with: event)
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        // Right click to toggle between paint and camera control
        if transferFunction.isPaintMode || transferFunction.isEraseMode {
            // Temporarily disable paint mode for camera control
            allowsCameraControl = true
        }
        super.rightMouseDown(with: event)
    }
}