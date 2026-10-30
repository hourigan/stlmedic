import AppKit
import Observation
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class Workspace {
    var inputURL: URL?
    var original: EngineResult?
    var repaired: EngineResult?
    var showingOriginal = false
    var scene = SCNScene()
    var settings = RepairSettings()
    var wireframe = false { didSet { applyDisplayOptions() } }
    var showIssues = true { didSet { applyDisplayOptions() } }
    var busy = false
    var activity = ""
    var operationTitle = ""
    var operationFileName = ""
    var operationProgress: EngineProgress?
    var operationStartedAt = Date()
    var stageStartedAt = Date()
    var error: String?
    var notice: String?
    var cameraReset = 0
    private var job: Task<Void, Never>?
    private var currentJobID: UUID?
    private var originalScene: SCNScene?
    private var repairedScene: SCNScene?
    private var importedURL: URL?
    private let sessionDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("STLMedic-\(UUID().uuidString)")

    var current: EngineResult? { showingOriginal ? original : (repaired ?? original) }
    var canExport: Bool { repaired != nil && !busy }
    var fileName: String { inputURL?.lastPathComponent ?? "No model open" }

    func chooseFile() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "stl") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an STL to inspect and repair. Your source file is preserved."
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func load(_ url: URL) {
        guard !busy else { return }
        guard url.pathExtension.lowercased() == "stl" else {
            error = "Choose a file in STL format. Both binary and ASCII STL are supported."
            return
        }
        begin(command: "analyze", input: url)
    }

    func demo() { guard !busy else { return }; begin(command: "demo", input: nil) }
    func repair() {
        guard !busy, let importedURL else { return }
        begin(command: "repair", input: importedURL)
    }

    private func begin(command: String, input: URL?) {
        let id = UUID()
        currentJobID = id
        busy = true
        notice = nil
        operationTitle = command == "repair" ? (settings.mode == "rebuild" ? "Rebuilding surface" : "Repairing model") : "Inspecting model"
        operationFileName = command == "repair" ? fileName : (input?.lastPathComponent ?? "Damaged demo model")
        operationStartedAt = Date()
        stageStartedAt = operationStartedAt
        let totalStages = command == "repair" ? 6 : 4
        operationProgress = EngineProgress(step: 1, total: totalStages, title: "Load model", message: "Starting the mesh engine…")
        activity = command == "repair" ? "Repairing and validating exported geometry…" : "Inspecting mesh topology and intersections…"
        let output = sessionDirectory.appendingPathComponent(id.uuidString)
        let options = settings
        job = Task {
            do {
                let result = try await EngineRunner.run(command: command, input: input, output: output, settings: options) { update in
                    await MainActor.run {
                        guard self.currentJobID == id else { return }
                        if self.operationProgress?.step != update.step { self.stageStartedAt = Date() }
                        self.operationProgress = update
                        self.activity = update.message
                    }
                }
                try Task.checkCancellation()
                guard currentJobID == id else { return }
                stageStartedAt = Date()
                operationProgress = EngineProgress(step: totalStages, total: totalStages,
                                                  title: "Display model", message: "Loading the interactive 3D preview…")
                activity = "Loading the interactive 3D preview…"
                let newScene = try await Task.detached(priority: .userInitiated) {
                    try MeshScene.load(result: result)
                }.value
                try Task.checkCancellation()
                guard currentJobID == id else { return }
                if command == "repair" {
                    repaired = result
                    repairedScene = newScene
                    showingOriginal = false
                    notice = result.report.checksPassed ? "Repair complete. Mesh checks passed." : "Repair complete. Some checks still need attention."
                } else {
                    inputURL = URL(fileURLWithPath: result.input)
                    importedURL = URL(fileURLWithPath: result.snapshot)
                    original = result
                    originalScene = newScene
                    repairedScene = nil
                    repaired = nil
                    showingOriginal = false
                }
                scene = newScene
                applyDisplayOptions()
                cameraReset += 1
            } catch is CancellationError {
                // Cancel leaves the last complete inspection available.
            } catch {
                guard currentJobID == id else { return }
                self.error = error.localizedDescription
            }
            if currentJobID == id { busy = false; job = nil }
        }
    }

    func cancel() {
        job?.cancel()
        currentJobID = nil
        busy = false
        operationProgress = nil
        notice = "Operation cancelled. Your source file is unchanged."
    }

    func changeComparison(_ original: Bool) {
        showingOriginal = original
        if let cachedScene = original ? originalScene : (repairedScene ?? originalScene) {
            scene = cachedScene
            applyDisplayOptions()
            cameraReset += 1
        }
    }

    private func applyDisplayOptions() {
        scene.rootNode.childNode(withName: "surface", recursively: true)?.geometry?.firstMaterial?.fillMode = wireframe ? .lines : .fill
        scene.rootNode.childNode(withName: "issues", recursively: true)?.isHidden = !showIssues
    }

    func export(openInBambu: Bool = false) {
        guard let result = repaired, let path = result.repaired, !busy else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "stl") ?? .data]
        panel.nameFieldStringValue = (inputURL?.deletingPathExtension().lastPathComponent ?? "Model") + "_repaired.stl"
        panel.message = result.report.checksPassed ? "Save the validated binary STL." : "Some mesh checks have not passed. Inspect this repair before printing."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.resolvingSymlinksInPath().standardizedFileURL != inputURL?.resolvingSymlinksInPath().standardizedFileURL else {
            error = "Choose a new filename to keep your source STL intact."
            return
        }
        do {
            try Data(contentsOf: URL(fileURLWithPath: path)).write(to: destination, options: .atomic)
            notice = "Saved \(destination.lastPathComponent)"
            if openInBambu {
                let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.bambulab.bambu-studio")
                    ?? ["/Applications/BambuStudio.app", "/Applications/Bambu Studio.app"].map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
                guard let application else {
                    notice = "STL saved. Open it in Bambu Studio to slice; Bambu Studio was not found in Applications."
                    return
                }
                NSWorkspace.shared.open([destination], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error { Task { @MainActor in self.error = error.localizedDescription } }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func exportReport() {
        guard let result = current else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(inputURL?.deletingPathExtension().lastPathComponent ?? "Model")_report.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let source = URL(fileURLWithPath: result.preview).deletingLastPathComponent().appendingPathComponent("result.json")
            try Data(contentsOf: source).write(to: url, options: .atomic)
            notice = "Inspection report saved."
        } catch { self.error = error.localizedDescription }
    }
}
