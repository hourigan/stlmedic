import Foundation

struct MeshReport: Codable, Sendable {
    let vertices, triangles, boundaryEdges, nonManifoldEdges, nonManifoldVertices: Int
    let boundaryGroups, inconsistentEdges, shells, isolatedVertices: Int
    let degenerateTriangles, duplicateTriangles, invertedShells: Int
    let dimensions: [Double]
    let watertight, windingConsistent, checksPassed: Bool
    let volume: Double?
    let intersectingTriangles: Int?

    var issueCount: Int {
        boundaryEdges + nonManifoldEdges + nonManifoldVertices + isolatedVertices
        + degenerateTriangles + duplicateTriangles + inconsistentEdges + invertedShells
        + (intersectingTriangles ?? 0)
    }
    var dimensionsLabel: String {
        dimensions.map { String(format: "%.2f", $0) }.joined(separator: " × ") + " mm"
    }
}

struct EngineResult: Decodable, Sendable {
    let report, before: MeshReport
    let notes: [String]
    let preview, input, snapshot: String
    let repaired: String?
    let previewTriangles: Int?

    var hasSimplifiedPreview: Bool { (previewTriangles ?? report.triangles) < report.triangles }
}

struct RepairSettings: Sendable {
    var mode = "robust"
    var tolerance = 0.0
    var largest = false
    var union = false
}

struct EngineProgress: Decodable, Equatable, Sendable {
    let step, total: Int
    let title, message: String

    // The active stage is still in progress; the bar counts completed stages.
    var completedStages: Double { Double(max(0, min(step - 1, total))) }
}

struct AppFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A lock protects cancellation that may arrive before Process.run().
final class ProcessTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func start(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        try process.run()
        self.process = process
    }
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }
}

enum EngineRunner {
    static func run(command: String, input: URL?, output: URL, settings: RepairSettings,
                    onProgress: @escaping @Sendable (EngineProgress) async -> Void = { _ in }) async throws -> EngineResult {
        let ticket = ProcessTicket()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                let resources = Bundle.main.resourceURL!
                let bundledPython = resources.appendingPathComponent("Python/bin/python3")
                let working = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let python = FileManager.default.isExecutableFile(atPath: bundledPython.path)
                    ? bundledPython : working.appendingPathComponent(".venv/bin/python")
                let script = FileManager.default.fileExists(atPath: resources.appendingPathComponent("Engine/engine.py").path)
                    ? resources.appendingPathComponent("Engine/engine.py") : working.appendingPathComponent("Engine/engine.py")
                guard FileManager.default.isExecutableFile(atPath: python.path) else {
                    throw AppFailure(message: "The bundled repair runtime is missing. Run scripts/build.sh to build the complete app.")
                }
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let log = output.appendingPathComponent("engine.log")
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let logHandle = try FileHandle(forWritingTo: log)
                defer { try? logHandle.close() }
                let process = Process()
                process.executableURL = python
                // Never write Python bytecode into the signed app bundle.
                var args = ["-I", "-B", script.path, command, "--output", output.path]
                if let input { args += ["--input", input.path] }
                if command == "repair" {
                    args += ["--mode", settings.mode, "--tolerance", String(settings.tolerance)]
                    if settings.largest { args.append("--largest") }
                    if settings.union { args.append("--union") }
                }
                process.arguments = args
                process.standardOutput = logHandle
                process.standardError = logHandle
                var environment = ProcessInfo.processInfo.environment
                environment["OPENBLAS_NUM_THREADS"] = "2"
                environment["OMP_NUM_THREADS"] = "2"
                process.environment = environment
                try ticket.start(process)
                let inputSize = input.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
                let timeLimit: TimeInterval = inputSize >= 50_000_000 ? 1800 : 300
                let deadline = Date().addingTimeInterval(timeLimit)
                let progressURL = output.appendingPathComponent("progress.json")
                var previousProgress: EngineProgress?
                while process.isRunning {
                    if let data = try? Data(contentsOf: progressURL),
                       let update = try? JSONDecoder().decode(EngineProgress.self, from: data),
                       update.total > 0, update.step > 0, update.step < update.total,
                       update != previousProgress {
                        previousProgress = update
                        await onProgress(update)
                    }
                    if Date() > deadline {
                        ticket.cancel()
                        process.waitUntilExit()
                        throw AppFailure(message: "Processing exceeded the \(Int(timeLimit / 60))-minute limit. Try Cleanup only or a smaller STL.")
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                process.waitUntilExit()
                let resultURL = output.appendingPathComponent("result.json")
                guard let data = try? Data(contentsOf: resultURL) else {
                    throw AppFailure(message: "The repair engine stopped unexpectedly. Your original file is unchanged. Try Cleanup only.")
                }
                if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = object["error"] as? String {
                    throw AppFailure(message: error)
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(EngineResult.self, from: data)
            }.value
        } onCancel: {
            ticket.cancel()
        }
    }
}
