import AppKit
import SceneKit
import SwiftUI

enum MeshScene {
    static func load(result: EngineResult) throws -> SCNScene {
        let data = try Data(contentsOf: URL(fileURLWithPath: result.preview))
        guard data.count >= 84 else { throw AppFailure(message: "The preview STL is incomplete.") }
        func float(_ offset: Int) -> Float {
            data.withUnsafeBytes { Float(bitPattern: UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))) }
        }
        let count = data.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self))) }
        guard count > 0, count <= 6_000_000, data.count == 84 + count * 50 else {
            throw AppFailure(message: "The preview STL has an invalid triangle table.")
        }
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var points = [SIMD3<Float>]()
        points.reserveCapacity(count * 3)
        for i in 0..<count {
            for corner in 0..<3 {
                let offset = 84 + i * 50 + 12 + corner * 12
                let p = SIMD3(float(offset), float(offset + 4), float(offset + 8))
                low = simd_min(low, p); high = simd_max(high, p)
                points.append(p)
            }
        }
        let center = (low + high) / 2
        let extent = high - low
        let scale = 90 / max(extent.x, extent.y, extent.z, 0.00001)
        func transform(_ p: SIMD3<Float>) -> SCNVector3 {
            let p = (p - center) * scale
            return SCNVector3(p.x, p.z, -p.y)
        }
        let vertices = points.map(transform)
        var normals = [SCNVector3]()
        normals.reserveCapacity(vertices.count)
        for i in stride(from: 0, to: points.count, by: 3) {
            let cross = simd_cross(points[i + 1] - points[i], points[i + 2] - points[i])
            let normal = simd_length(cross) > 0 ? simd_normalize(cross) : SIMD3<Float>(0, 0, 1)
            let n = SCNVector3(normal.x, normal.z, -normal.y)
            normals.append(contentsOf: [n, n, n])
        }
        let indices = (0..<(count * 3)).map { Int32($0) }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(calibratedRed: 0.27, green: 0.78, blue: 0.67, alpha: 1)
        material.lightingModel = .blinn
        material.specular.contents = NSColor(white: 0.25, alpha: 1)
        material.shininess = 0.25
        material.isDoubleSided = true
        geometry.materials = [material]
        let surface = SCNNode(geometry: geometry)
        surface.name = "surface"
        let scene = SCNScene()
        scene.background.contents = NSColor(calibratedRed: 0.065, green: 0.085, blue: 0.11, alpha: 1)
        scene.rootNode.addChildNode(surface)

        let edgeURL = URL(fileURLWithPath: result.preview).deletingLastPathComponent().appendingPathComponent("edges.bin")
        if let edgeData = try? Data(contentsOf: edgeURL), !edgeData.isEmpty {
            var edges = [SCNVector3]()
            for i in stride(from: 0, to: edgeData.count - 11, by: 12) {
                let p: SIMD3<Float> = edgeData.withUnsafeBytes { buffer in
                    func f(_ o: Int) -> Float { Float(bitPattern: UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: o, as: UInt32.self))) }
                    return SIMD3(f(i), f(i + 4), f(i + 8))
                }
                edges.append(transform(p))
            }
            let node = lineNode(edges, color: NSColor.systemOrange)
            node.name = "issues"
            node.geometry?.firstMaterial?.readsFromDepthBuffer = false
            node.renderingOrder = 10
            scene.rootNode.addChildNode(node)
        }
        let floor = -extent.z * scale / 2 - 0.6
        var grid = [SCNVector3]()
        for i in -7...7 {
            let p = Float(i * 10)
            grid += [SCNVector3(p, floor, -70), SCNVector3(p, floor, 70),
                     SCNVector3(-70, floor, p), SCNVector3(70, floor, p)]
        }
        scene.rootNode.addChildNode(lineNode(grid, color: NSColor(white: 0.22, alpha: 0.5)))
        let camera = SCNNode()
        camera.name = "camera"
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 2000
        camera.camera?.fieldOfView = 42
        camera.position = SCNVector3(125, 85, 150)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 200
        scene.rootNode.addChildNode(ambient)
        for (position, intensity) in [(SCNVector3(80, 140, 130), CGFloat(950)), (SCNVector3(-100, 30, -40), CGFloat(350))] {
            let node = SCNNode()
            node.light = SCNLight()
            node.light?.type = .directional
            node.light?.intensity = intensity
            node.position = position
            node.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(node)
        }
        return scene
    }

    private static func lineNode(_ vertices: [SCNVector3], color: NSColor) -> SCNNode {
        let element = SCNGeometryElement(indices: (0..<vertices.count).map { Int32($0) }, primitiveType: .line)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}

struct MeshViewport: NSViewRepresentable {
    let scene: SCNScene
    let reset: Int

    final class Coordinator { var reset = -1 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.defaultCameraController.inertiaEnabled = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if view.scene !== scene || context.coordinator.reset != reset {
            view.scene = scene
            view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: true)
            view.pointOfView?.position = SCNVector3(125, 85, 150)
            view.pointOfView?.look(at: SCNVector3Zero)
            view.defaultCameraController.target = SCNVector3Zero
            context.coordinator.reset = reset
        }
    }
}
