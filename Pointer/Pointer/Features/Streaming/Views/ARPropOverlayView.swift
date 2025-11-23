//
//  ARPropOverlayView.swift
//  Pointer
//
//  Created by Ron Kibel on 11/12/25.
//

import SwiftUI
import SceneKit

/// AR Prop overlay that renders a 3D model and draws its bounding box
struct ARPropOverlayView: View {
    let poseData: PoseData
    let imageSize: CGSize
    @State private var sceneView: SCNView?
    
    var body: some View {
        ZStack {
            ModelSceneView(poseData: poseData, sceneViewBinding: $sceneView)
                .background(Color.clear)
            
            if let sceneView = sceneView {
                ARBoxOverlay(sceneView: sceneView)
            }
        }
    }
}

struct ModelSceneView: UIViewRepresentable {
    let poseData: PoseData
    @Binding var sceneViewBinding: SCNView?
    
    // Helper method to compute bounding box corners in world space
    static func getBBoxWorldCorners(node: SCNNode) -> [SCNVector3] {
        let (min, max) = node.boundingBox
        let halfWidth = (max.x - min.x) * node.scale.x / 2
        let halfHeight = (max.y - min.y) * node.scale.y / 2
        let halfDepth = (max.z - min.z) * node.scale.z / 2
        
        let corners = [
            SCNVector3(-halfWidth, -halfHeight, -halfDepth), SCNVector3(halfWidth, -halfHeight, -halfDepth),
            SCNVector3(halfWidth, halfHeight, -halfDepth), SCNVector3(-halfWidth, halfHeight, -halfDepth),
            SCNVector3(-halfWidth, -halfHeight, halfDepth), SCNVector3(halfWidth, -halfHeight, halfDepth),
            SCNVector3(halfWidth, halfHeight, halfDepth), SCNVector3(-halfWidth, halfHeight, halfDepth)
        ]
        
        func rotate(_ v: SCNVector3, by q: SCNQuaternion) -> SCNVector3 {
            let u = SCNVector3(q.x, q.y, q.z)
            let uv = SCNVector3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            let uuv = SCNVector3(u.y * uv.z - u.z * uv.y, u.z * uv.x - u.x * uv.z, u.x * uv.y - u.y * uv.x)
            return SCNVector3(v.x + 2.0 * (q.w * uv.x + uuv.x), v.y + 2.0 * (q.w * uv.y + uuv.y), v.z + 2.0 * (q.w * uv.z + uuv.z))
        }
        
        return corners.map { corner -> SCNVector3 in
            let rotated = rotate(corner, by: node.presentation.orientation)
            return SCNVector3(
                rotated.x + node.position.x,
                rotated.y + node.position.y,
                rotated.z + node.position.z
            )
        }
    }
    
    // Helper to calculate letterboxing scale and offset
    static func calculateLetterbox(viewBounds: CGRect, imageSize: [Int]) -> (scale: CGFloat, offset: CGPoint) {
        let imageWidth = CGFloat(imageSize[0])
        let imageHeight = CGFloat(imageSize[1])
        let viewAspect = viewBounds.width / viewBounds.height
        let imageAspect = imageWidth / imageHeight
        
        if viewAspect > imageAspect {
            let scale = viewBounds.height / imageHeight
            return (scale, CGPoint(x: (viewBounds.width - imageWidth * scale) / 2, y: 0))
        } else {
            let scale = viewBounds.width / imageWidth
            return (scale, CGPoint(x: 0, y: (viewBounds.height - imageHeight * scale) / 2))
        }
    }
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = true
        
        let camera = SCNNode()
        camera.camera = SCNCamera()
        view.scene?.rootNode.addChildNode(camera)
        view.pointOfView = camera
        
        if let url = Bundle.main.url(forResource: "Drill", withExtension: "usdz"),
           let scene = try? SCNScene(url: url, options: nil) {
            let node = SCNNode()
            scene.rootNode.childNodes.forEach { node.addChildNode($0.clone()) }
            
            let (minVec, maxVec) = node.boundingBox
            node.pivot = SCNMatrix4MakeTranslation((minVec.x + maxVec.x)/2, (minVec.y + maxVec.y)/2, (minVec.z + maxVec.z)/2)
            
            node.name = "drill"
            node.scale = SCNVector3(0.1, 0.1, 0.1)
            view.scene?.rootNode.addChildNode(node)
        }
        
        DispatchQueue.main.async { sceneViewBinding = view }
        return view
    }
    
    func updateUIView(_ view: SCNView, context: Context) {
        guard let node = view.scene?.rootNode.childNode(withName: "drill", recursively: true),
              let euler = poseData.getSceneKitEulerAngles() else { return }
        
        // Helper: Unproject 2D point to 3D at fixed depth
        let desiredZ: Float = -5.0
        func unproject(_ p: CGPoint) -> SCNVector3 {
            let near = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
            let far = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
            let t = (desiredZ - near.z) / (far.z - near.z)
            return SCNVector3(near.x + t * (far.x - near.x), near.y + t * (far.y - near.y), desiredZ)
        }

        // 1. Determine target screen point (Top Face Center or BBox Center)
        let topFace = poseData.getTopFace() ?? []
        let points = !topFace.isEmpty ? topFace : poseData.getProjectedBoundingBox()
        guard !points.isEmpty else { return }
        
        let avg = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let target2D = CGPoint(x: avg.x / CGFloat(points.count), y: avg.y / CGFloat(points.count))
        
        // 2. Apply letterboxing & Rotation
        let (scale, offset) = ModelSceneView.calculateLetterbox(viewBounds: view.bounds, imageSize: poseData.imageSize)
        let screenPoint = CGPoint(x: target2D.x * scale + offset.x, y: target2D.y * scale + offset.y)
        node.eulerAngles = SCNVector3(euler.x, euler.y, euler.z)
        
        // 3. Adjust scale based on top face size
        if !topFace.isEmpty {
            let unprojected = topFace.map { unproject(CGPoint(x: $0.x * scale + offset.x, y: $0.y * scale + offset.y)) }
            let center = unprojected.reduce(SCNVector3Zero) { SCNVector3($0.x + $1.x, $0.y + $1.y, $0.z + $1.z) }
            let c = SCNVector3(center.x / Float(unprojected.count), center.y / Float(unprojected.count), center.z / Float(unprojected.count))
            
            let maxRadius = unprojected.map { sqrt(pow($0.x - c.x, 2) + pow($0.y - c.y, 2) + pow($0.z - c.z, 2)) }.max() ?? 0.1
            let (min, max) = node.boundingBox
            let propRadius = sqrt(pow(max.x - min.x, 2) + pow(max.z - min.z, 2)) / 2.0
            let newScale = (Float(maxRadius) / Float(propRadius)) * 0.7
            node.scale = SCNVector3(newScale, newScale, newScale)
        }

        // 4. Align node so its BOTTOM FACE center matches target
        node.position = SCNVector3(0, 0, desiredZ)
        let corners = ModelSceneView.getBBoxWorldCorners(node: node)
        let bottomSum = [0, 1, 4, 5].reduce(SCNVector3Zero) { sum, i in 
            let c = corners[i]; return SCNVector3(sum.x + c.x, sum.y + c.y, sum.z + c.z) 
        }
        let bottomCenter = SCNVector3(bottomSum.x / 4, bottomSum.y / 4, bottomSum.z / 4)
        
        let currentProj = view.projectPoint(bottomCenter)
        let targetProj = view.projectPoint(unproject(screenPoint))
        let adjusted = view.unprojectPoint(SCNVector3(targetProj.x, targetProj.y, currentProj.z))
        
        node.position = SCNVector3(
            node.position.x + (adjusted.x - bottomCenter.x),
            node.position.y + (adjusted.y - bottomCenter.y),
            node.position.z + (adjusted.z - bottomCenter.z)
        )
    }
}

struct ARBoxOverlay: View {
    let sceneView: SCNView
    @State private var updateTrigger = false
    
    var body: some View {
        Canvas { context, size in
            guard let drillNode = sceneView.scene?.rootNode.childNode(withName: "drill", recursively: true),
                  let camera = sceneView.pointOfView else { return }

            // Project corners
            let fov = CGFloat(camera.camera?.fieldOfView ?? 60.0) * .pi / 180.0
            let tanHalfFov = tan(fov / 2.0)
            let aspect = sceneView.bounds.width / sceneView.bounds.height
            
            let projected = ModelSceneView.getBBoxWorldCorners(node: drillNode).compactMap { p -> CGPoint? in
                guard p.z < -0.01 else { return nil }
                let ndcX = CGFloat(p.x) / (CGFloat(-p.z) * tanHalfFov * aspect)
                let ndcY = CGFloat(p.y) / (CGFloat(-p.z) * tanHalfFov)
                return CGPoint(x: (ndcX + 1.0) * sceneView.bounds.width / 2.0, y: (1.0 - ndcY) * sceneView.bounds.height / 2.0)
            }
            guard projected.count == 8 else { return }
            
            // Draw bounding box edges
            let edges = [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]
            edges.forEach { edge in
                context.stroke(Path { p in p.move(to: projected[edge.0]); p.addLine(to: projected[edge.1]) }, with: .color(.cyan), lineWidth: 2)
            }
        }
        .onAppear { Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { _ in updateTrigger.toggle() } }
        .onChange(of: updateTrigger) { _ in }
    }
}
