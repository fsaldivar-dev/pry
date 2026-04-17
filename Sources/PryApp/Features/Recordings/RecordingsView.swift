import SwiftUI
import PryLib

/// UI para gestionar grabaciones de tráfico: start/stop + lista + convertir a mocks.
@available(macOS 14, *)
struct RecordingsView: View {
    @Environment(AppCore.self) private var core

    @State private var newRecordingName: String = ""
    @State private var filterDomains: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

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
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Grabando: \(name)").font(.headline)
                                Text("\(core.recordings.currentStepCount) request(s) capturados")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Stop") { core.recordings.stop() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Nombre de la grabación", text: $newRecordingName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(startRecording)
                            Button("Start", action: startRecording)
                                .disabled(newRecordingName.trimmingCharacters(in: .whitespaces).isEmpty)
                                .buttonStyle(.borderedProminent)
                        }
                        TextField("Filtrar dominios (opcional, separados por coma)", text: $filterDomains)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
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
        .alert("Recordings", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @MainActor
    private func startRecording() {
        let name = newRecordingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let domains = filterDomains
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        core.recordings.start(name: name, domains: domains)
        newRecordingName = ""
        filterDomains = ""
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
