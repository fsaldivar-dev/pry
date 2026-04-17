import SwiftUI
import PryLib

/// UI para gestionar grabaciones de tráfico: start/stop + lista + convertir a mocks.
@available(macOS 14, *)
struct RecordingsView: View {
    @Environment(AppCore.self) private var core

    @State private var newRecordingName: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Controles de grabación.
            VStack(alignment: .leading, spacing: 10) {
                if core.recordings.isRecording {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle.fill")
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, options: .repeating)
                        if let name = core.recordings.currentRecordingName {
                            Text("Grabando: \(name)")
                                .font(.headline)
                        } else {
                            Text("Grabando…").font(.headline)
                        }
                        Spacer()
                        Button("Stop") {
                            core.recordings.stop()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                } else {
                    HStack {
                        TextField("Nombre de la grabación", text: $newRecordingName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(startRecording)
                        Button("Start", action: startRecording)
                            .disabled(newRecordingName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()

            Divider()

            // Lista de grabaciones guardadas.
            if core.recordings.recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No hay grabaciones guardadas")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(core.recordings.recordings, id: \.self) { name in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.blue.opacity(0.8))
                            Text(name)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("To mocks") {
                                let count = core.recordings.toMocks(name: name)
                                errorMessage = "Se convirtieron \(count) mock(s)"
                                showErrorAlert = true
                            }
                            .buttonStyle(.bordered)
                            Button {
                                core.recordings.delete(name: name)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Recordings")
        .alert("Mocks generados", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    @MainActor
    private func startRecording() {
        let name = newRecordingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        core.recordings.start(name: name)
        newRecordingName = ""
    }
}

@available(macOS 14, *)
struct RecordingsView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingsView()
            .environment(AppCore.preview())
            .frame(width: 500, height: 400)
    }
}
