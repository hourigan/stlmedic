import SwiftUI

struct Inspector: View {
    @Bindable var workspace: Workspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                HStack {
                    SectionCaption(text: "MESH INSPECTION")
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.secondary)
                }
                if let result = workspace.current {
                    status(result.report)
                    statistics(result.report)
                    diagnostics(result)
                    VStack(alignment: .leading, spacing: 11) {
                        SectionCaption(text: "INSPECTION NOTES")
                        ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                            Text(note).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
                        }
                        Text("Orange lines mark boundary and non-manifold edges. Self-intersections and thin-wall printability are not highlighted.")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(3)
                    }
                    Button("Export inspection report…") { workspace.exportReport() }
                        .font(.system(size: 11)).disabled(workspace.busy)
                    if workspace.canExport {
                        Button { workspace.export(openInBambu: true) } label: {
                            Label("Save & open in Bambu Studio", systemImage: "arrow.up.forward.app")
                                .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.bordered)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "checkmark.shield").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.secondary)
                        Text("Know what needs fixing.").font(.system(size: 15, weight: .medium))
                        Text("Open a model to inspect its topology, surface quality, and watertightness.")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                    }.padding(.vertical, 16)
                    VStack(spacing: 0) {
                        ForEach(["Non-manifold edges", "Non-manifold vertices", "Isolated vertices", "Degenerate triangles", "Duplicate triangles", "Open boundaries", "Inconsistent winding", "Reversed shells", "Self-intersections"], id: \.self) { label in
                            HStack { Text(label); Spacer(); Text("—").foregroundStyle(Theme.secondary) }
                                .font(.system(size: 11)).padding(.vertical, 11)
                            Divider().overlay(Theme.line)
                        }
                    }
                }
            }.padding(20)
        }.background(Theme.panel.opacity(0.6))
    }

    private func status(_ report: MeshReport) -> some View {
        let passed = report.checksPassed
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22)).foregroundStyle(passed ? Theme.mint : .orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(passed ? "Mesh checks passed" : "Needs attention").font(.system(size: 14, weight: .semibold))
                Text(passed ? "Closed, manifold, and consistently oriented. Confirm the sliced layers before printing."
                     : "Review the checks below, then repair and inspect the result.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background((passed ? Theme.mint : .orange).opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statistics(_ report: MeshReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCaption(text: "GEOMETRY")
            HStack {
                stat("TRIANGLES", report.triangles.formatted())
                Spacer()
                stat("VERTICES", report.vertices.formatted())
                Spacer()
                stat("SHELLS", report.shells.formatted())
            }
            Text(report.dimensionsLabel).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 16, weight: .medium, design: .rounded))
            Text(title).font(.system(size: 8, design: .monospaced)).foregroundStyle(Theme.secondary)
        }
    }

    private func diagnostics(_ result: EngineResult) -> some View {
        let r = result.report
        let before = workspace.repaired != nil && !workspace.showingOriginal ? workspace.original?.report : nil
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionCaption(text: "SURFACE CHECKS")
                Spacer()
                if before != nil { Text("BEFORE → NOW").font(.system(size: 8, design: .monospaced)).foregroundStyle(Theme.secondary) }
            }.padding(.bottom, 13)
            check("Non-manifold edges", r.nonManifoldEdges, before?.nonManifoldEdges)
            check("Non-manifold vertices", r.nonManifoldVertices, before?.nonManifoldVertices)
            check("Isolated vertices", r.isolatedVertices, before?.isolatedVertices)
            check("Degenerate triangles", r.degenerateTriangles, before?.degenerateTriangles)
            check("Duplicate triangles", r.duplicateTriangles, before?.duplicateTriangles)
            check("Boundary edges", r.boundaryEdges, before?.boundaryEdges)
            check("Boundary loops / groups", r.boundaryGroups, before?.boundaryGroups)
            check("Inconsistent winding", r.inconsistentEdges, before?.inconsistentEdges)
            check("Negative-volume shells", r.invertedShells, before?.invertedShells)
            check("Intersecting triangles", r.intersectingTriangles, before?.intersectingTriangles)
            HStack {
                Image(systemName: r.watertight ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(r.watertight ? Theme.mint : .orange)
                Text("Watertight")
                Spacer()
                Text(r.watertight ? "Yes" : "No").foregroundStyle(r.watertight ? Theme.mint : .orange)
            }.font(.system(size: 11)).padding(.vertical, 11)
        }
    }

    private func check(_ title: String, _ count: Int?, _ before: Int?) -> some View {
        HStack(spacing: 7) {
            Image(systemName: count == 0 ? "checkmark.circle.fill" : (count == nil ? "questionmark.circle" : "exclamationmark.circle.fill"))
                .foregroundStyle(count == 0 ? Theme.mint : (count == nil ? Theme.secondary : .orange))
                .font(.system(size: 10))
            Text(title).font(.system(size: 11))
            Spacer(minLength: 3)
            if let before {
                Text("\(before.formatted()) →").foregroundStyle(Theme.secondary).font(.system(size: 9, design: .monospaced))
            } else if workspace.repaired != nil && !workspace.showingOriginal {
                Text("— →").foregroundStyle(Theme.secondary).font(.system(size: 9, design: .monospaced))
            }
            Text(count.map { $0.formatted() } ?? "Unchecked")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(count == 0 ? Theme.mint : (count == nil ? Theme.secondary : .orange))
        }.padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
