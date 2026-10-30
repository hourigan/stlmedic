import SwiftUI

struct OperationProgressView: View {
    let workspace: Workspace

    var body: some View {
        TimelineView(.periodic(from: workspace.operationStartedAt, by: 1)) { context in
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 13) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 22)).foregroundStyle(Theme.mint)
                        .frame(width: 42, height: 42)
                        .background(Theme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(workspace.operationTitle).font(.system(size: 17, weight: .semibold))
                        Text(workspace.operationFileName)
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    ProgressView().controlSize(.small).accessibilityLabel("Processing model")
                }
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 8) {
                    Text(workspace.operationProgress?.title ?? "Starting…")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mint)
                    Text(workspace.activity)
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                }
                if let progress = workspace.operationProgress {
                    ProgressView(value: progress.completedStages, total: Double(progress.total))
                        .progressViewStyle(.linear).tint(Theme.mint)
                        .accessibilityLabel("Completed processing stages")
                        .accessibilityValue("\(Int(progress.completedStages)) of \(progress.total) stages completed")
                    HStack {
                        Text("Stage \(progress.step) of \(progress.total)")
                        Spacer()
                        Text("Elapsed \(elapsed(since: workspace.operationStartedAt, now: context.date))")
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                }
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("This stage: \(elapsed(since: workspace.stageStartedAt, now: context.date))")
                            .monospacedDigit()
                        Text("Some stages can take several minutes.")
                    }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 0)
                    Button("Cancel", role: .cancel) { workspace.cancel() }
                        .buttonStyle(.bordered).controlSize(.regular)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1) }
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        }
    }

    private func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
