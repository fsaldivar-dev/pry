import SwiftUI
import AppKit
import PryKit
import PryLib

/// Notification usada por el menú Edit → Find (⌘F) para pedirle a la
/// RequestListView que enfoque su NSSearchField. El menú no puede acceder
/// directamente al `@FocusState` de la view, así que usamos NotificationCenter
/// como bridge — es simple, no requiere cambios estructurales en la UI
/// existente, y la view ya expone `SearchFieldView.activeField` como weak
/// reference estática que podemos usar como fallback.
@available(macOS 14, *)
public enum PryMenuNotification {
    public static let focusSearch = Notification.Name("PryApp.FocusSearch")
}

/// Comandos del menú bar (Edit / Proxy / File) para PryApp.
///
/// Scope P0 del issue #85 — se agregan en `WindowGroup { ... }.commands { }`
/// de `PryApp.swift`. Recibe los managers como dependencies vía init porque
/// los closures de `.commands { }` no pueden usar `@Environment` directamente.
@available(macOS 14, *)
@MainActor
struct PryCommands: Commands {
    let proxy: ProxyManager
    let store: RequestStoreWrapper
    let core: AppCore

    var body: some Commands {
        // MARK: Edit menu
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy as cURL") {
                copyAsCurl(store: store)
            }
            .keyboardShortcut("c", modifiers: [.option, .command])
            // No podemos deshabilitar el item dinámicamente desde el closure de
            // Commands sin agregar @ObservedObject-style bindings. Si no hay
            // selección, la acción muestra un alert — ver copyAsCurl().

            Button("Copy URL") {
                copySelectedURL(store: store)
            }
            .keyboardShortcut("c", modifiers: [.shift, .command])

            Button("Find") {
                NotificationCenter.default.post(name: PryMenuNotification.focusSearch, object: nil)
                // Fallback directo por si la view no observa la notificación.
                SearchFieldView.activeField?.window?.makeFirstResponder(SearchFieldView.activeField)
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Clear Traffic") {
                store.clear()
            }
            .keyboardShortcut("k", modifiers: [.command])
        }

        // MARK: Proxy menu
        CommandMenu("Proxy") {
            Button("Start Proxy") {
                do {
                    try proxy.start(interceptors: core.interceptors, eventBus: core.bus)
                } catch {
                    presentError("No se pudo iniciar el proxy", detail: "\(error)")
                }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(proxy.isRunning)

            Button("Stop Proxy") {
                proxy.stop()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!proxy.isRunning)

            Button("Restart Proxy") {
                proxy.stop()
                do {
                    try proxy.start(interceptors: core.interceptors, eventBus: core.bus)
                } catch {
                    presentError("No se pudo reiniciar el proxy", detail: "\(error)")
                }
            }
            .keyboardShortcut("r", modifiers: [.shift, .command])

            Divider()

            Toggle(isOn: Binding(
                get: { proxy.systemProxyEnabled },
                set: { newValue in
                    if newValue {
                        proxy.enableSystemProxy()
                    } else {
                        proxy.disableSystemProxy()
                    }
                }
            )) {
                Text("Enable System Proxy")
            }

            Divider()

            Button("Install CA in Simulator") {
                installCAInSimulator()
            }
        }

        // MARK: File menu (replaces `.newItem`)
        CommandGroup(replacing: .newItem) {
            Button("Import Scenario…") {
                importScenarioFromPanel()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Export Current Scenario…") {
                exportCurrentScenarioWithPanel()
            }
            .keyboardShortcut("e", modifiers: [.command])
        }
    }
}

// MARK: - Helpers

@available(macOS 14, *)
@MainActor
private func copyAsCurl(store: RequestStoreWrapper) {
    guard let req = store.selectedRequest else {
        presentInfo("No hay request seleccionado", detail: "Seleccioná un request de la lista para copiarlo como cURL.")
        return
    }
    // Usamos https si el host sugiere TLS (heurística simple). En el detail
    // view real del futuro, podemos exponer isHTTPS en CapturedRequest.
    let curl = CurlGenerator.generate(from: req)
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(curl, forType: .string)
}

@available(macOS 14, *)
@MainActor
private func copySelectedURL(store: RequestStoreWrapper) {
    guard let req = store.selectedRequest else {
        presentInfo("No hay request seleccionado", detail: "Seleccioná un request de la lista para copiar su URL.")
        return
    }
    let url = "\(req.host)\(req.url)"
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(url, forType: .string)
}

@available(macOS 14, *)
@MainActor
private func importScenarioFromPanel() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.init(filenameExtension: "pryscenario") ?? .json]
    panel.title = "Importar escenario"
    panel.prompt = "Importar"

    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        let name = try ScenarioExporter.importScenario(from: url.path)
        presentInfo("Escenario importado", detail: "Se importó como \"\(name)\".")
    } catch {
        presentError("No se pudo importar el escenario", detail: "\(error)")
    }
}

@available(macOS 14, *)
@MainActor
private func exportCurrentScenarioWithPanel() {
    guard let active = ScenarioManager.active() else {
        presentInfo("No hay escenario activo", detail: "Activá un escenario primero (Proxy → scenarios) para poder exportarlo.")
        return
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(active).pryscenario"
    panel.allowedContentTypes = [.init(filenameExtension: "pryscenario") ?? .json]
    panel.title = "Exportar escenario"
    panel.prompt = "Exportar"

    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        try ScenarioExporter.export(name: active, to: url.path)
        presentInfo("Escenario exportado", detail: "Guardado en \(url.path).")
    } catch {
        presentError("No se pudo exportar el escenario", detail: "\(error)")
    }
}

/// Ejecuta `pry trust` (binario CLI) para instalar el CA en el iOS Simulator.
/// Sigue la misma estrategia de resolución del binario que ProxyManager.
@available(macOS 14, *)
@MainActor
private func installCAInSimulator() {
    guard let binary = resolvePryBinary() else {
        presentError(
            "No se encontró el binario `pry`",
            detail: "Instalá el CLI (por ejemplo `brew install pry` o `make install`) para poder instalar el CA en el Simulator."
        )
        return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["trust"]
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            presentInfo("CA instalado", detail: "El certificado fue instalado en los iOS Simulators activos.")
        } else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            presentError("Falló `pry trust`", detail: err.isEmpty ? "Revisá que haya un Simulator corriendo." : err)
        }
    } catch {
        presentError("No se pudo ejecutar `pry trust`", detail: "\(error)")
    }
}

/// Resolución del binario `pry` — mismo orden que `ProxyManager.resolvePryBinary`:
/// 1. sibling del ejecutable actual, 2. /usr/local/bin, 3. /opt/homebrew/bin.
@MainActor
private func resolvePryBinary() -> String? {
    let fm = FileManager.default
    var candidates: [String] = []
    if let exec = Bundle.main.executablePath {
        let sibling = (exec as NSString).deletingLastPathComponent + "/pry"
        candidates.append(sibling)
    }
    candidates.append("/usr/local/bin/pry")
    candidates.append("/opt/homebrew/bin/pry")
    for c in candidates where fm.isExecutableFile(atPath: c) {
        return c
    }
    return nil
}

@available(macOS 14, *)
@MainActor
private func presentInfo(_ message: String, detail: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = detail
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

@available(macOS 14, *)
@MainActor
private func presentError(_ message: String, detail: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = detail
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
}
