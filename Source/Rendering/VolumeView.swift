import SwiftUI
import SceneKit

struct VolumeView: NSViewRepresentable {
    
    // The node that contains the volume rendering
    var volumeCube: SCNNode
    
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
        
        // Add the pre-configured volume cube to the scene
        scene.rootNode.addChildNode(volumeCube)
        
        return scnView
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
        // Updates to the view go here
    }
} 