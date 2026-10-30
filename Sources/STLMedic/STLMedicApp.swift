import SwiftUI
import AppKit

@main
struct STLMedicApp: App {
    @State private var workspace = Workspace()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView(workspace: workspace)
                .frame(minWidth: 1080, minHeight: 720)
                .preferredColorScheme(.dark)
                .tint(Theme.mint)
                .onOpenURL { workspace.load($0) }
                .task {
                    delegate.workspace = workspace
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("--demo") { workspace.demo() }
                    else if let path = args.dropFirst().first(where: { $0.lowercased().hasSuffix(".stl") }) {
                        workspace.load(URL(fileURLWithPath: path))
                    }
                }
        }
        .defaultSize(width: 1340, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About STL Medic") { AboutPanel.show() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open STL…") { workspace.chooseFile() }.keyboardShortcut("o").disabled(workspace.busy)
                Button("Open damaged demo") { workspace.demo() }.disabled(workspace.busy)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Export Repaired STL…") { workspace.export() }.keyboardShortcut("s").disabled(!workspace.canExport)
                Button("Export Inspection Report…") { workspace.exportReport() }.disabled(workspace.current == nil || workspace.busy)
            }
            CommandMenu("Mesh") {
                Button("Repair Model") { workspace.repair() }.keyboardShortcut("r").disabled(workspace.inputURL == nil || workspace.busy)
                Button("Reset Camera") { workspace.cameraReset += 1 }.keyboardShortcut("0")
                Toggle("Wireframe", isOn: $workspace.wireframe).keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: Workspace?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { workspace?.cancel() }
}
