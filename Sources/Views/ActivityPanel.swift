import SwiftUI
import AppKit

// ActivityPanel.swift
// The strip along the bottom of the detail area. It appears while a backup, restore or encryption
// change runs (title, progress, elapsed time, Stop), stays to show how the job ended (finished,
// failed or stopped, with advice), and carries the result line of short actions such as Restart.
// The tool's own output is available in a log that can be opened underneath.

struct ActivityPanel: View {
    @EnvironmentObject var model: Model
    @AppStorage("showLog") private var showLog = false

    private var hasJob: Bool {
        return model.busy || model.outcome != .none
    }

    /// The model reports a refused start (for example Back Up while nothing is connected) through
    /// `status` alone, without an outcome. Show that sentence so it is not lost.
    private var refusal: String {
        if hasJob { return "" }
        if model.status.isEmpty || model.status == "Ready." { return "" }
        return model.status
    }

    var body: some View {
        if hasJob || !model.actionMessage.isEmpty || !refusal.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if !model.actionMessage.isEmpty {
                        ActionMessageLine()
                    }
                    if !refusal.isEmpty {
                        RefusalLine(text: refusal)
                    }
                    if hasJob {
                        jobArea
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
    }

    @ViewBuilder private var jobArea: some View {
        if model.busy {
            RunningJobView(showLog: $showLog)
        } else {
            FinishedJobView(showLog: $showLog)
        }
        if showLog {
            LogView()
        }
    }
}

// MARK: - Wording

enum JobWording {
    /// Heading for a job that is running or has ended.
    static func heading(kind: OperationKind, outcome: OperationOutcome, busy: Bool, deviceName: String) -> String {
        let target = deviceName.isEmpty ? "" : " “\(deviceName)”"
        if busy {
            switch kind {
            case .backup: return "Backing up" + target
            case .restore: return "Restoring" + target
            case .encryptionOn: return "Turning on backup encryption"
            case .encryptionOff: return "Turning off backup encryption"
            case .changePassword: return "Changing the backup password"
            case .none: return "Working"
            }
        }
        switch outcome {
        case .success:
            switch kind {
            case .backup: return "Backup finished"
            case .restore: return "Restore finished"
            case .encryptionOn: return "Backup encryption is now on"
            case .encryptionOff: return "Backup encryption is now off"
            case .changePassword: return "Backup password changed"
            case .none: return "Finished"
            }
        case .failure:
            switch kind {
            case .backup: return "Backup failed"
            case .restore: return "Restore failed"
            case .encryptionOn: return "Backup encryption was not turned on"
            case .encryptionOff: return "Backup encryption was not turned off"
            case .changePassword: return "The backup password was not changed"
            case .none: return "Failed"
            }
        case .cancelled:
            switch kind {
            case .backup: return "Backup stopped"
            case .restore: return "Restore stopped"
            case .encryptionOn, .encryptionOff, .changePassword: return "Stopped before the change was made"
            case .none: return "Stopped"
            }
        case .none:
            return ""
        }
    }

    static func symbol(for outcome: OperationOutcome) -> String {
        switch outcome {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .cancelled: return "minus.circle.fill"
        case .none: return "circle"
        }
    }

    static func tint(for outcome: OperationOutcome) -> Color {
        switch outcome {
        case .success: return .green
        case .failure: return .red
        case .cancelled: return .secondary
        case .none: return .secondary
        }
    }

    /// Spoken by VoiceOver in place of the symbol.
    static func spoken(for outcome: OperationOutcome) -> String {
        switch outcome {
        case .success: return "Succeeded"
        case .failure: return "Failed"
        case .cancelled: return "Stopped"
        case .none: return ""
        }
    }
}

// MARK: - Running

struct RunningJobView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    @Binding var showLog: Bool

    private var heading: String {
        return JobWording.heading(kind: model.operation, outcome: .none, busy: true, deviceName: ui.jobDeviceName)
    }

    private var line: String {
        if !model.stage.isEmpty { return model.stage }
        return model.status
    }

    private var stopTitle: String {
        return model.cancelling ? "Stopping…" : "Stop"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(heading)
                    .font(.headline)
                Spacer(minLength: 8)
                Text("Elapsed " + model.elapsedText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                LogToggle(showLog: $showLog)
                Button(stopTitle) { ui.requestStop(model) }
                    .disabled(model.cancelling)
                    .help("Stop the job that is running")
            }
            JobProgressBar(progress: model.progress)
            Text(line)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.currentFile.isEmpty || model.fileProgress > 0 {
                CurrentFileLine(name: model.currentFile, progress: model.fileProgress)
            }
        }
    }
}

/// Determinate once the tool has reported progress; a moving bar before that.
struct JobProgressBar: View {
    let progress: Double

    private var clamped: Double {
        return min(max(progress, 0), 1)
    }

    private var percentText: String {
        return String(Int((clamped * 100).rounded())) + "%"
    }

    var body: some View {
        HStack(spacing: 10) {
            if progress > 0 {
                ProgressView(value: clamped, total: 1)
                    .progressViewStyle(.linear)
                    .accessibilityLabel(Text("Progress"))
                Text(percentText)
                    .font(.callout)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel(Text("Working"))
            }
        }
    }
}

struct CurrentFileLine: View {
    let name: String
    let progress: Double

    private var text: String {
        let percent = Int((min(max(progress, 0), 1) * 100).rounded())
        if name.isEmpty { return "Current file: \(percent)%" }
        return "Current file: \(name) (\(percent)%)"
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

// MARK: - Ended

struct FinishedJobView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    @Binding var showLog: Bool

    private var heading: String {
        return JobWording.heading(kind: model.operation, outcome: model.outcome, busy: false, deviceName: ui.jobDeviceName)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: JobWording.symbol(for: model.outcome))
                .font(.title2)
                .foregroundStyle(JobWording.tint(for: model.outcome))
                .accessibilityLabel(Text(JobWording.spoken(for: model.outcome)))
            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .font(.headline)
                Text(model.status)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !model.errorHint.isEmpty {
                    Text(model.errorHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if model.elapsed > 0 {
                    Text("Took " + model.elapsedText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            LogToggle(showLog: $showLog)
            Button("Dismiss") { model.acknowledgeOutcome() }
        }
    }
}

// MARK: - Short actions

/// Result (or progress) of restart, shut down, pairing, archive and similar quick actions.
struct ActionMessageLine: View {
    @EnvironmentObject var model: Model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if model.actionBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Working"))
            } else {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(model.actionMessage)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if !model.actionBusy {
                Button {
                    model.actionMessage = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Hide this message")
                .accessibilityLabel(Text("Hide this message"))
            }
        }
    }
}

/// A start that the model refused, with the reason it gave.
struct RefusalLine: View {
    @EnvironmentObject var model: Model
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel(Text("Warning"))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Dismiss") { model.acknowledgeOutcome() }
                .controlSize(.small)
        }
    }
}

// MARK: - Log

struct LogToggle: View {
    @Binding var showLog: Bool

    var body: some View {
        Button {
            showLog.toggle()
        } label: {
            Label(showLog ? "Hide Log" : "Show Log", systemImage: showLog ? "chevron.down" : "chevron.right")
        }
        .help("Show or hide what the backup tool printed")
    }
}

/// What the command-line tool printed, in a fixed-height scrolling box that follows the newest line.
struct LogView: View {
    @EnvironmentObject var model: Model

    private var text: String {
        return model.logText.isEmpty ? "Nothing has been logged yet." : model.logText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        Color.clear
                            .frame(height: 1)
                            .id("logEnd")
                    }
                }
                .onChange(of: model.logText) { _ in
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
            }
            .frame(height: 170)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .accessibilityLabel(Text("Log"))
            HStack(spacing: 10) {
                Button("Copy Log") { model.copyLog() }
                    .disabled(model.logText.isEmpty)
                Button("Clear Log") { model.clearLog() }
                    .disabled(model.logText.isEmpty)
                Spacer()
                if !model.toolVersion.isEmpty {
                    Text("idevicebackup2 " + model.toolVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
        }
    }
}
