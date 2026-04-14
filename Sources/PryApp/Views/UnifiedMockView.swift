import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
struct UnifiedMockView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectUIManager.self) private var projectManager
    @Environment(RecorderUIManager.self) private var recorder

    enum Selection: Hashable {
        case looseMocks
        case project(String)
        case scenario(project: String, scenario: String)
    }

    @State private var selection: Selection = .looseMocks
    @State private var showAddMock = false
    @State private var showNewProject = false
    @State private var showNewScenario = false
    @State private var newName = ""
    @State private var selectedProject = ""  // for new scenario dialog

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Mocking")
                    .font(.headline)

                if let label = projectManager.activeLabel {
                    Text(label)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(PryTheme.success.opacity(0.2))
                        .foregroundStyle(PryTheme.success)
                        .clipShape(Capsule())
                }

                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Main content: sidebar + detail
            HStack(spacing: 0) {
                // LEFT: Navigation sidebar
                navigationSidebar
                    .frame(width: 200)

                Divider()

                // RIGHT: Content
                contentPanel
            }
        }
        .alert("New Project", isPresented: $showNewProject) {
            TextField("Project name", text: $newName)
            Button("Create") {
                if !newName.isEmpty {
                    try? projectManager.createProject(name: newName)
                    newName = ""
                }
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .alert("New Scenario", isPresented: $showNewScenario) {
            TextField("Scenario name", text: $newName)
            Button("Create") {
                if !newName.isEmpty {
                    try? projectManager.createScenario(project: selectedProject, name: newName)
                    newName = ""
                }
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .sheet(isPresented: $showAddMock) {
            AddUnifiedMockView(selection: selection)
                .frame(minWidth: 450, minHeight: 350)
        }
    }

    // MARK: - Navigation Sidebar

    private var navigationSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Loose Mocks section
                Button {
                    selection = .looseMocks
                } label: {
                    HStack {
                        Image(systemName: "theatermask.and.paintbrush")
                            .foregroundStyle(SwiftUI.Color.purple)
                        Text("Loose Mocks")
                            .font(.system(size: 12, weight: selection == .looseMocks ? .bold : .regular))
                        Spacer()
                        Text("\(MockEngine.shared.looseMockList().count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(selection == .looseMocks ? PryTheme.accent.opacity(0.1) : SwiftUI.Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.vertical, 4)

                // Projects section header
                HStack {
                    Text("PROJECTS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PryTheme.textTertiary)
                        .tracking(1.5)
                    Spacer()
                    Button {
                        showNewProject = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)

                // Project list
                ForEach(projectManager.projects, id: \.self) { project in
                    projectRow(project)
                }

                if projectManager.projects.isEmpty {
                    Text("No projects yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
            }
            .padding(8)
        }
        .background(PryTheme.bgPanel)
    }

    private func projectRow(_ project: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Project header
            Button {
                selection = .project(project)
            } label: {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(PryTheme.accent)
                        .font(.caption)
                    Text(project)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selection == .project(project) ? PryTheme.accent.opacity(0.1) : SwiftUI.Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Scenarios under project
            let scenarios = projectManager.listScenarios(project: project)
            ForEach(scenarios, id: \.self) { scenario in
                Button {
                    selection = .scenario(project: project, scenario: scenario)
                } label: {
                    HStack(spacing: 4) {
                        let isActive = projectManager.activeProject == project && projectManager.activeScenario == scenario
                        Circle()
                            .fill(isActive ? PryTheme.success : SwiftUI.Color.clear)
                            .frame(width: 6, height: 6)
                        Image(systemName: "film")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(scenario)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
                    .background(scenarioBackground(project: project, scenario: scenario))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func scenarioBackground(project: String, scenario: String) -> SwiftUI.Color {
        if case .scenario(project, scenario) = selection {
            return PryTheme.accent.opacity(0.1)
        }
        return SwiftUI.Color.clear
    }

    // MARK: - Content Panel

    private var contentPanel: some View {
        VStack(spacing: 0) {
            switch selection {
            case .looseMocks:
                looseMocksPanel
            case .project(let project):
                projectDetailPanel(project)
            case .scenario(let project, let scenario):
                scenarioDetailPanel(project: project, scenario: scenario)
            }
        }
    }

    // Loose mocks panel
    private var looseMocksPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Loose Mocks")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    showAddMock = true
                } label: {
                    Image(systemName: "plus")
                    Text("Add Mock")
                }
                .controlSize(.small)

                if !MockEngine.shared.looseMockList().isEmpty {
                    Button {
                        MockEngine.shared.clearLooseMocks()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            let mocks = MockEngine.shared.looseMockList()
            if mocks.isEmpty {
                ContentUnavailableView(
                    "No Loose Mocks",
                    systemImage: "theatermask.and.paintbrush",
                    description: Text("Quick, temporary mocks. Add one or right-click a request.")
                )
            } else {
                List {
                    ForEach(mocks, id: \.id) { mock in
                        UnifiedMockRow(mock: mock) {
                            MockEngine.shared.removeLooseMock(id: mock.id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // Project detail panel (shows scenarios list)
    private func projectDetailPanel(_ project: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(project)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    selectedProject = project
                    showNewScenario = true
                } label: {
                    Image(systemName: "plus")
                    Text("New Scenario")
                }
                .controlSize(.small)

                Button {
                    projectManager.deleteProject(name: project)
                    selection = .looseMocks
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            let scenarios = projectManager.listScenarios(project: project)
            if scenarios.isEmpty {
                ContentUnavailableView(
                    "No Scenarios",
                    systemImage: "film.stack",
                    description: Text("Create a scenario to group mocks for this project")
                )
            } else {
                List {
                    ForEach(scenarios, id: \.self) { scenario in
                        let isActive = projectManager.activeProject == project && projectManager.activeScenario == scenario
                        HStack {
                            Circle()
                                .fill(isActive ? PryTheme.success : SwiftUI.Color.clear)
                                .frame(width: 8, height: 8)
                            Image(systemName: "film")
                                .foregroundStyle(PryTheme.accent)
                            Text(scenario)
                                .font(.system(size: 13))
                            Spacer()

                            if isActive {
                                Button("Deactivate") {
                                    projectManager.deactivate()
                                }
                                .controlSize(.small)
                            } else {
                                Button("Activate") {
                                    projectManager.activate(project: project, scenario: scenario)
                                }
                                .controlSize(.small)
                                .tint(PryTheme.success)
                            }

                            Button {
                                selection = .scenario(project: project, scenario: scenario)
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // Scenario detail panel (shows mocks in this scenario)
    private func scenarioDetailPanel(project: String, scenario: String) -> some View {
        VStack(spacing: 0) {
            let isActive = projectManager.activeProject == project && projectManager.activeScenario == scenario

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario)
                        .font(.subheadline.weight(.medium))
                    Text(project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PryTheme.success.opacity(0.2))
                        .foregroundStyle(PryTheme.success)
                        .clipShape(Capsule())
                }

                Spacer()

                if isActive {
                    Button("Deactivate") {
                        projectManager.deactivate()
                    }
                    .controlSize(.small)
                } else {
                    Button {
                        projectManager.activate(project: project, scenario: scenario)
                    } label: {
                        Image(systemName: "play.fill")
                        Text("Activate")
                    }
                    .controlSize(.small)
                    .tint(PryTheme.success)
                }

                Button {
                    showAddMock = true
                } label: {
                    Image(systemName: "plus")
                    Text("Add Mock")
                }
                .controlSize(.small)

                Button {
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        recorder.start(name: "\(project)-\(scenario)")
                    }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle")
                    Text(recorder.isRecording ? "Stop" : "Record")
                }
                .controlSize(.small)
                .tint(recorder.isRecording ? .red : nil)

                Button {
                    projectManager.deleteScenario(project: project, scenario: scenario)
                    selection = .project(project)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if let scenarioData = projectManager.loadScenario(project: project, scenario: scenario) {
                if scenarioData.mocks.isEmpty {
                    ContentUnavailableView(
                        "No Mocks",
                        systemImage: "theatermask.and.paintbrush",
                        description: Text("Add mocks to this scenario or record traffic")
                    )
                } else {
                    List {
                        ForEach(scenarioData.mocks, id: \.id) { mock in
                            UnifiedMockRow(mock: mock) {
                                // Remove mock from scenario
                                var updated = scenarioData
                                updated.mocks.removeAll { $0.id == mock.id }
                                try? projectManager.saveScenario(updated, project: project)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                ContentUnavailableView(
                    "Scenario Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Could not load scenario data")
                )
            }
        }
    }
}

// MARK: - Reusable Mock Row

@available(macOS 14, *)
private struct UnifiedMockRow: View {
    let mock: UnifiedMock
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            // Method badge
            Text(mock.method ?? "ANY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(PryTheme.methodColor(mock.method).opacity(0.2))
                .foregroundStyle(PryTheme.methodColor(mock.method))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            // Pattern
            VStack(alignment: .leading, spacing: 1) {
                Text(mock.pattern)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                if !mock.body.isEmpty && mock.body != "{}" {
                    Text(mock.body.prefix(60))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Delay
            if let delay = mock.delay, delay > 0 {
                Text("\(delay)ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Status badge
            Text("\(mock.status)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(PryTheme.statusColorSwiftUI(mock.status))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(PryTheme.statusColorSwiftUI(mock.status).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Delete
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .confirmationDialog("Delete mock for \(mock.pattern)?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }
}

// MARK: - Add Mock View

@available(macOS 14, *)
private struct AddUnifiedMockView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectUIManager.self) private var projectManager
    let selection: UnifiedMockView.Selection

    @State private var pattern = ""
    @State private var method = "ANY"
    @State private var status: UInt = 200
    @State private var bodyText = "{}"
    @State private var delay = ""

    private let methods = ["ANY", "GET", "POST", "PUT", "PATCH", "DELETE"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Mock")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Form {
                TextField("URL Pattern (e.g. /api/users)", text: $pattern)
                    .font(.system(size: 12, design: .monospaced))

                Picker("Method", selection: $method) {
                    ForEach(methods, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }

                HStack {
                    Text("Status")
                    TextField("", value: $status, format: .number)
                        .frame(width: 60)
                    // Quick status buttons
                    ForEach([200, 400, 401, 404, 500], id: \.self) { code in
                        Button("\(code)") { status = UInt(code) }
                            .font(.system(size: 10, design: .monospaced))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }

                TextField("Delay (ms)", text: $delay)

                Section("Response Body") {
                    TextEditor(text: $bodyText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 100)
                }
            }
            .padding(12)

            Divider()

            HStack {
                // Show destination
                Text("-> \(destinationLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") {
                    saveMock()
                    dismiss()
                }
                .disabled(pattern.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
    }

    private var destinationLabel: String {
        switch selection {
        case .looseMocks: return "Loose Mocks"
        case .project(let p): return "Project: \(p)"
        case .scenario(let p, let s): return "\(p) / \(s)"
        }
    }

    private func saveMock() {
        let mock = UnifiedMock(
            method: method == "ANY" ? nil : method,
            pattern: pattern,
            status: status,
            body: bodyText,
            delay: Int(delay),
            source: .loose,
            isEnabled: true
        )

        switch selection {
        case .looseMocks:
            MockEngine.shared.addLooseMock(mock)
        case .project:
            // Add as loose mock when no specific scenario selected
            MockEngine.shared.addLooseMock(mock)
        case .scenario(let project, let scenario):
            if var scenarioData = projectManager.loadScenario(project: project, scenario: scenario) {
                let scenarioMock = UnifiedMock(
                    method: mock.method, pattern: mock.pattern, host: mock.host,
                    status: mock.status, headers: mock.headers, body: mock.body,
                    delay: mock.delay, notes: mock.notes,
                    source: .scenario(project: project, scenario: scenario),
                    isEnabled: true
                )
                scenarioData.mocks.append(scenarioMock)
                try? projectManager.saveScenario(scenarioData, project: project)
            }
        }
    }
}
