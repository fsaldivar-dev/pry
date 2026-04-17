import Foundation
import Observation
import PryLib

/// Store de grabaciones de tráfico. Feature "Recordings" del ADR-006.
///
/// Observer pattern: no muta el flow del proxy (no es un `Interceptor`).
/// Escucha al `EventBus` para reaccionar a eventos de ciclo de vida en el
/// futuro; por ahora wrapea el singleton legacy `Recorder.shared` que ya
/// tiene los hooks `noteRequestStart` / `noteResponseComplete` llamados
/// desde `HTTPInterceptor` y `TLSForwarder`.
///
/// Reemplaza a `RecorderUIManager` (PryKit) — éste se deprecará cuando
/// todos los consumers migren a `AppCore.recordings`.
@available(macOS 14, *)
@Observable
@MainActor
public final class RecordingsStore {
    /// Si hay una grabación en curso.
    public var isRecording: Bool = false

    /// Lista de nombres de grabaciones guardadas.
    public var recordings: [String] = []

    /// Nombre de la grabación actualmente activa (nil si no está grabando).
    public var currentRecordingName: String?

    private let bus: EventBus

    public init(bus: EventBus) {
        self.bus = bus
        reload()
    }

    // MARK: - Actions

    /// Refresca el estado desde el singleton legacy + lista de archivos en disco.
    public func reload() {
        isRecording = Recorder.shared.isRecording
        recordings = Recorder.list().sorted()
    }

    /// Empieza una grabación nueva. `domains` opcionales filtran qué tráfico se graba.
    public func start(name: String, domains: [String] = []) {
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return }
        Recorder.shared.start(name: sanitized, domains: domains)
        isRecording = true
        currentRecordingName = sanitized
        publishChange()
    }

    /// Termina la grabación actual. Guarda a disco y retorna el Recording
    /// resultante (o nil si no había ninguna activa).
    @discardableResult
    public func stop() -> Recording? {
        let result = Recorder.shared.stop()
        isRecording = false
        currentRecordingName = nil
        reload()
        publishChange()
        return result
    }

    /// Elimina una grabación guardada.
    public func delete(name: String) {
        Recorder.delete(name: name)
        reload()
        publishChange()
    }

    /// Convierte una grabación guardada en mocks (para el MockEngine legacy).
    /// Retorna cantidad de mocks creados.
    public func toMocks(name: String) -> Int {
        Recorder.toMocks(name: name)
    }

    /// Carga una grabación desde disco (para visualización).
    public func load(name: String) -> Recording? {
        Recorder.load(name: name)
    }

    private func publishChange() {
        let snapshot = recordings
        let recording = isRecording
        let bus = self.bus
        Task { await bus.publish(RecordingsChangedEvent(names: snapshot, isRecording: recording)) }
    }
}
