import SwiftUI
import UniformTypeIdentifiers

enum Theme {
    static let mint = Color(red: 0.36, green: 0.86, blue: 0.71)
    static let background = Color(red: 0.055, green: 0.071, blue: 0.09)
    static let panel = Color(red: 0.085, green: 0.102, blue: 0.125)
    static let line = Color.white.opacity(0.09)
    static let secondary = Color(red: 0.56, green: 0.61, blue: 0.67)
}

struct ContentView: View {
    @Bindable var workspace: Workspace
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 0) {
                sidebar.frame(width: 245)
                Rectangle().fill(Theme.line).frame(width: 1)
                viewport.frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Theme.line).frame(width: 1)
                Inspector(workspace: workspace).frame(width: 302)
            }
            footer
        }
        .background(Theme.background)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard !workspace.busy, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in workspace.load(url) } }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).stroke(Theme.mint, lineWidth: 3).padding(6).allowsHitTesting(false)
            }
        }
        .alert("Unable to complete operation", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            Button("OK", role: .cancel) { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.transparent.fill").font(.system(size: 25)).foregroundStyle(Theme.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("STL Medic").font(.system(size: 17, weight: .semibold))
                Text("A better mesh. A better print.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Label("ON-DEVICE REPAIR", systemImage: "lock.shield")
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.secondary)
            Rectangle().fill(Theme.line).frame(width: 1, height: 24).padding(.horizontal, 8)
            Button { workspace.chooseFile() } label: { Label("Open STL", systemImage: "folder") }.disabled(workspace.busy)
            Button { workspace.export() } label: { Label("Export STL", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent).disabled(!workspace.canExport)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 18)
    }

    private var sidebar: some View {
        GeometryReader { geometry in
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 13) {
                SectionCaption(text: "WORKSPACE")
                Label("Mesh repair", systemImage: "cross.case")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.mint).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionCaption(text: "SOURCE MODEL")
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.zipper").font(.title2).foregroundStyle(Theme.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(workspace.fileName).font(.system(size: 12, weight: .medium)).lineLimit(3).textSelection(.enabled)
                        Text(workspace.original == nil ? "Binary or ASCII STL" : "Original preserved")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
                if let report = workspace.original?.report {
                    Text(report.dimensionsLabel).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                }
            }
            Divider().overlay(Theme.line)
            RepairControls(workspace: workspace)
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 9) {
                Label("Made for your next print", systemImage: "printer").font(.system(size: 11, weight: .medium))
                Text("Export a repaired STL, open it in Bambu Studio, and check the sliced layers before printing.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
            }
            .padding(13).background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(18).frame(minHeight: geometry.size.height)
        }
        }.background(Theme.panel.opacity(0.6))
    }

    private var viewport: some View {
        ZStack {
            if workspace.current != nil {
                MeshViewport(scene: workspace.scene, reset: workspace.cameraReset)
                VStack {
                    HStack {
                        Label(workspace.current?.hasSimplifiedPreview == true ? "3D PREVIEW · SIMPLIFIED" : "3D PREVIEW", systemImage: "cube").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Theme.secondary)
                            .help("Display detail may be reduced for large models. Repair and export retain full resolution.")
                        Spacer()
                        if workspace.repaired != nil {
                            Picker("Preview version", selection: Binding(get: { workspace.showingOriginal }, set: { workspace.changeComparison($0) })) {
                                Text("Original").tag(true)
                                Text("Repaired").tag(false)
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 180).disabled(workspace.busy)
                        }
                    }
                    Spacer()
                    HStack {
                        Text("Drag to orbit · Scroll to zoom · Option-drag to pan")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        Spacer()
                    }
                }.padding(20)
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Toggle(isOn: $workspace.wireframe) { Image(systemName: "square.3.layers.3d") }
                            .help("Toggle wireframe").accessibilityLabel("Wireframe")
                        Toggle(isOn: $workspace.showIssues) { Image(systemName: "exclamationmark.triangle") }
                            .help("Highlight boundary and non-manifold edges (up to 20,000)").accessibilityLabel("Highlight problem edges")
                        Button { workspace.cameraReset += 1 } label: { Image(systemName: "viewfinder") }.help("Reset camera")
                    }
                    .toggleStyle(.button).buttonStyle(.bordered).padding(10)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 54)
                }
            } else { emptyState }
            if workspace.busy {
                Color.black.opacity(0.4)
                OperationProgressView(workspace: workspace)
                    .padding(24)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Theme.mint.opacity(0.04)).frame(width: 170, height: 170)
                Circle().stroke(Theme.mint.opacity(0.12), lineWidth: 1).frame(width: 140, height: 140)
                Image(systemName: "cube.transparent").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(Theme.mint)
                Image(systemName: "plus.circle.fill").font(.system(size: 25)).foregroundStyle(Theme.mint).offset(x: 42, y: 36)
            }
            VStack(spacing: 9) {
                Text("Give your model a fresh start.").font(.system(size: 23, weight: .medium))
                Text("Drop an STL here to find and repair mesh issues.\nEverything stays on your Mac.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).lineSpacing(5)
            }
            Button("Choose STL file…") { workspace.chooseFile() }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("Try a damaged demo model") { workspace.demo() }.buttonStyle(.plain).foregroundStyle(Theme.secondary).font(.system(size: 12))
            Text("BINARY & ASCII STL  ·  UP TO 6M TRIANGLES")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary.opacity(0.65))
        }.padding(25)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(workspace.busy ? Color.orange : Theme.mint).frame(width: 5, height: 5)
            Text(workspace.busy ? workspace.activity : (workspace.notice ?? "Ready when you are"))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text("STL unit assumption: mm").foregroundStyle(Theme.secondary)
        }
        .font(.system(size: 10)).padding(.horizontal, 18).padding(.vertical, 11)
        .background(Theme.panel)
    }
}

struct SectionCaption: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(Theme.secondary)
    }
}
