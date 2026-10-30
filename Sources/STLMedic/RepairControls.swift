import SwiftUI

struct RepairControls: View {
    @Bindable var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionCaption(text: "REPAIR SETTINGS")
            Picker("Method", selection: $workspace.settings.mode) {
                Text("Robust repair").tag("robust")
                Text("Cleanup only").tag("cleanup")
                Text("Rebuild surface").tag("rebuild")
            }.pickerStyle(.menu)
            Text(methodDescription)
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Weld nearby vertices").font(.system(size: 12))
                Picker("Weld tolerance", selection: $workspace.settings.tolerance) {
                    Text("Exact matches only").tag(0.0)
                    Text("0.001 mm").tag(0.001)
                    Text("0.01 mm").tag(0.01)
                    Text("0.1 mm").tag(0.1)
                }.labelsHidden().frame(maxWidth: .infinity)
            }
            Toggle("Keep largest shell only", isOn: $workspace.settings.largest)
                .font(.system(size: 11))
                .help("Discards all disconnected shells except the one with the largest surface area.")
            Toggle("Union overlapping solids", isOn: $workspace.settings.union)
                .font(.system(size: 11))
                .help("Combines overlapping closed solids. Nested shells become solid; intentional cavities may be filled.")
            if workspace.settings.largest || workspace.settings.union {
                Label("These options can remove parts or cavities.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
            if workspace.settings.mode == "rebuild" {
                Label("Rebuilding can smooth fine details and change dimensions.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { workspace.repair() } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text(workspace.repaired == nil ? "Repair model" : "Repair again")
                    Spacer()
                    Text("⌘R").foregroundStyle(.black.opacity(0.4))
                }.font(.system(size: 12, weight: .semibold)).padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .disabled(workspace.original == nil)
            Text("Always starts from your original.")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }.disabled(workspace.busy)
    }

    private var methodDescription: String {
        switch workspace.settings.mode {
        case "rebuild":
            return "Create a new surface for difficult meshes. Compare details and dimensions carefully before printing."
        case "cleanup":
            return "Remove duplicate and degenerate faces, weld vertices, and correct normals. Keep open boundaries."
        default:
            return "Close boundaries, repair topology, and resolve self-intersections. Geometry may change."
        }
    }
}
