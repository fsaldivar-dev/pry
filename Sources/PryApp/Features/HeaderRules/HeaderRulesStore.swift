import Foundation
import Observation
import PryLib

/// Acción que aplica una `HeaderRule` sobre los headers de una request.
///
/// - `set`: agrega o reemplaza el header con `value`. Reemplazo es case-insensitive
///   por nombre — si ya existe un header con el mismo nombre (en cualquier casing),
///   se sobreescribe preservando el casing nuevo.
/// - `remove`: elimina cualquier header cuyo nombre matchee (case-insensitive).
public enum HeaderRuleAction: String, Sendable, Equatable {
    case set
    case remove
}

/// Una regla de rewrite de headers. Value type inmutable — las mutaciones se
/// manejan a nivel del store reemplazando la colección.
///
/// Para `.remove`, `value` es irrelevante y se ignora (se guarda vacío por
/// conveniencia de persistencia).
public struct HeaderRule: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let action: HeaderRuleAction
    public let name: String
    public let value: String

    public init(id: UUID = UUID(), action: HeaderRuleAction, name: String, value: String = "") {
        self.id = id
        self.action = action
        self.name = name
        self.value = value
    }
}

/// Store de reglas de rewrite de headers. Reemplaza progresivamente al legacy
/// `HeaderRewrite` (PryLib) en el contexto de PryApp.
///
/// Persiste a un archivo configurable (típicamente `StoragePaths.headersFile`).
/// Formato `action\tname\tvalue` por línea — compatible con la intención del
/// legacy aunque sin compartir lector (migración progresiva).
///
/// Las reglas se aplican en orden de inserción sobre el diccionario de headers
/// de una `RequestContext` — `set` reemplaza case-insensitive, `remove` quita
/// todas las entries cuyo nombre matchee.
@available(macOS 14, *)
@Observable
@MainActor
public final class HeaderRulesStore {
    /// Lista actual de reglas, en orden de aplicación.
    public private(set) var rules: [HeaderRule] = []

    private let storagePath: String
    private let bus: EventBus

    /// - Parameters:
    ///   - storagePath: archivo donde persistir las reglas. `AppCore` pasa el path
    ///     canónico; los tests inyectan temp dirs.
    ///   - bus: bus al que publicar `HeaderRulesChangedEvent` tras mutaciones.
    public init(storagePath: String, bus: EventBus) {
        self.storagePath = storagePath
        self.bus = bus
        reload()
    }

    // MARK: - Actions

    /// Agrega una regla `set` (o reemplaza la existente si ya hay una `set` con
    /// el mismo nombre, case-insensitive). Name vacío → no-op.
    public func addSet(name: String, value: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        // Dedup: una sola regla `set` por nombre (case-insensitive).
        if let idx = rules.firstIndex(where: {
            $0.action == .set && $0.name.lowercased() == trimmedName.lowercased()
        }) {
            guard rules[idx].value != value || rules[idx].name != trimmedName else { return }
            rules[idx] = HeaderRule(id: rules[idx].id, action: .set, name: trimmedName, value: value)
        } else {
            rules.append(HeaderRule(action: .set, name: trimmedName, value: value))
        }
        persist()
        publishChange()
    }

    /// Agrega una regla `remove`. Name vacío → no-op. Dedup por nombre
    /// (case-insensitive) — una sola `remove` por nombre.
    public func addRemove(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        if rules.contains(where: {
            $0.action == .remove && $0.name.lowercased() == trimmedName.lowercased()
        }) {
            return
        }
        rules.append(HeaderRule(action: .remove, name: trimmedName))
        persist()
        publishChange()
    }

    /// Quita una regla específica por `id`. No-op si no existe.
    public func remove(rule: HeaderRule) {
        let before = rules.count
        rules.removeAll { $0.id == rule.id }
        if rules.count != before {
            persist()
            publishChange()
        }
    }

    /// Vacía la lista completa.
    public func clear() {
        guard !rules.isEmpty else { return }
        rules.removeAll()
        persist()
        publishChange()
    }

    private func publishChange() {
        let snapshot = rules.map { ($0.action.rawValue, $0.name, $0.value) }
        let bus = self.bus
        Task { await bus.publish(HeaderRulesChangedEvent(rules: snapshot)) }
    }

    // MARK: - Matching / apply

    /// Aplica todas las reglas en orden sobre `headers` y devuelve el resultado.
    ///
    /// - `.set` reemplaza cualquier header existente cuyo nombre matchee
    ///   case-insensitive (preservando el casing de la regla).
    /// - `.remove` elimina cualquier header cuyo nombre matchee case-insensitive.
    ///
    /// Si no hay reglas, retorna `headers` sin modificar.
    public func apply(to headers: [String: String]) -> [String: String] {
        guard !rules.isEmpty else { return headers }
        var result = headers
        for rule in rules {
            switch rule.action {
            case .set:
                // Remover cualquier key existente con mismo nombre (case-insensitive)
                // antes de agregar la nueva, para evitar duplicados con distinto casing.
                let lower = rule.name.lowercased()
                for key in result.keys where key.lowercased() == lower {
                    result.removeValue(forKey: key)
                }
                result[rule.name] = rule.value
            case .remove:
                let lower = rule.name.lowercased()
                for key in result.keys where key.lowercased() == lower {
                    result.removeValue(forKey: key)
                }
            }
        }
        return result
    }

    // MARK: - Persistence

    private func reload() {
        guard let content = try? String(contentsOfFile: storagePath, encoding: .utf8) else {
            rules = []
            return
        }
        rules = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count >= 2, let action = HeaderRuleAction(rawValue: String(parts[0])) else {
                    return nil
                }
                let name = String(parts[1])
                let value = parts.count > 2 ? String(parts[2]) : ""
                return HeaderRule(action: action, name: name, value: value)
            }
    }

    private func persist() {
        let content = rules.map { "\($0.action.rawValue)\t\($0.name)\t\($0.value)" }
            .joined(separator: "\n")
        let toWrite = rules.isEmpty ? "" : content + "\n"
        try? toWrite.write(toFile: storagePath, atomically: true, encoding: .utf8)
    }
}
