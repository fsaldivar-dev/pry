import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
struct RecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecorderUIManager.self) private var recorderManager
    @State private var recordingName = ""
    @State private var selectedRecording: String?
    @State private var showDetail = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Recorder")
                    .font(.headline)

                if recorderManager.isRecording {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .modifier(PulsingModifier())
                        Text("REC")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fontWeight(.bold)
                    }
                }

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Record controls
            VStack(spacing: 8) {
                if recorderManager.isRecording {
                    HStack {
                        Text("Recording in progress...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            recorderManager.stop()
                        } label: {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                } else {
                    HStack(spacing: 8) {
                        TextField("Recording name", text: $recordingName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))

                        Button {
                            guard !recordingName.isEmpty else { return }
                            recorderManager.start(name: recordingName)
                            recordingName = ""
                        } label: {
                            Image(systemName: "record.circle")
                            Text("Record")
                        }
                        .disabled(recordingName.isEmpty)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if recorderManager.recordings.isEmpty {
                ContentUnavailableView(
                    "No Recordings",
                    systemImage: "waveform",
                    description: Text("Start recording to capture traffic flows")
                )
            } else {
                List {
                    ForEach(recorderManager.recordings, id: \.self) { name in
                        RecordingRow(
                            name: name,
                            recording: recorderManager.load(name: name),
                            onShow: {
                                selectedRecording = name
                                showDetail = true
                            },
                            onToMocks: {
                                _ = recorderManager.toMocks(name: name)
                            },
                            onDelete: {
                                recorderManager.delete(name: name)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showDetail) {
            if let name = selectedRecording, let recording = recorderManager.load(name: name) {
                RecordingDetailView(recording: recording)
                    .frame(minWidth: 500, minHeight: 400)
            }
        }
    }
}

// Pulsing animation for REC indicator
private struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

@available(macOS 14, *)
private struct RecordingRow: View {
    let name: String
    let recording: Recording?
    let onShow: () -> Void
    let onToMocks: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(PryTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                if let r = recording {
                    Text("\(r.steps.count) steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onShow) {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .help("View Steps")

            Button(action: onToMocks) {
                Image(systemName: "theatermask.and.paintbrush")
            }
            .buttonStyle(.borderless)
            .help("Convert to Mocks")

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .confirmationDialog("Delete recording '\(name)'?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }
}

@available(macOS 14, *)
private struct RecordingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recording: Recording

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(recording.name)
                    .font(.headline)
                Text("\(recording.steps.count) steps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List {
                ForEach(Array(recording.steps.enumerated()), id: \.element.sequence) { _, step in
                    HStack(spacing: 8) {
                        Text("\(step.sequence)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Text(step.method)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(PryTheme.methodColor(step.method).opacity(0.2))
                            .foregroundStyle(PryTheme.methodColor(step.method))
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        Text(step.url)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)

                        Spacer()

                        if let status = step.statusCode {
                            Text("\(status)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(PryTheme.statusColorSwiftUI(status))
                        }

                        Text("\(step.latencyMs)ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

}
