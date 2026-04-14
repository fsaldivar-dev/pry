import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
struct ScenarioListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScenarioUIManager.self) private var scenarioManager
    @State private var showCreateDialog = false
    @State private var newScenarioName = ""
    @State private var selectedScenario: String?
    @State private var showJSON = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Scenarios")
                    .font(.headline)

                if let active = scenarioManager.activeScenario {
                    Text(active)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(PryTheme.success.opacity(0.2))
                        .foregroundStyle(PryTheme.success)
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    showCreateDialog = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create Scenario")

                if scenarioManager.activeScenario != nil {
                    Button {
                        scenarioManager.deactivate()
                    } label: {
                        Image(systemName: "stop.circle")
                    }
                    .help("Deactivate Scenario")
                }

                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if scenarioManager.scenarios.isEmpty {
                ContentUnavailableView(
                    "No Scenarios",
                    systemImage: "film.stack",
                    description: Text("Create a scenario to group mocks, headers, and rules")
                )
            } else {
                List {
                    ForEach(scenarioManager.scenarios, id: \.self) { name in
                        ScenarioRow(
                            name: name,
                            isActive: name == scenarioManager.activeScenario,
                            onActivate: {
                                scenarioManager.activate(name: name)
                            },
                            onShow: {
                                selectedScenario = name
                                showJSON = true
                            },
                            onDelete: {
                                scenarioManager.delete(name: name)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert("New Scenario", isPresented: $showCreateDialog) {
            TextField("Name", text: $newScenarioName)
            Button("Create") {
                if !newScenarioName.isEmpty {
                    try? scenarioManager.create(name: newScenarioName)
                    newScenarioName = ""
                }
            }
            Button("Cancel", role: .cancel) { newScenarioName = "" }
        }
        .sheet(isPresented: $showJSON) {
            if let name = selectedScenario, let scenario = scenarioManager.load(name: name) {
                ScenarioDetailView(scenario: scenario)
                    .frame(minWidth: 500, minHeight: 400)
            }
        }
    }
}

@available(macOS 14, *)
private struct ScenarioRow: View {
    let name: String
    let isActive: Bool
    let onActivate: () -> Void
    let onShow: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack {
            // Active indicator
            Circle()
                .fill(isActive ? PryTheme.success : Color.clear)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(PryTheme.success)
                }
            }

            Spacer()

            if !isActive {
                Button(action: onActivate) {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Activate")
            }

            Button(action: onShow) {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .help("View Details")

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .confirmationDialog("Delete scenario '\(name)'?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }
}

@available(macOS 14, *)
private struct ScenarioDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let scenario: Scenario

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(scenario.name)
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !scenario.watchlist.isEmpty {
                        sectionHeader("Watchlist", count: scenario.watchlist.count)
                        ForEach(scenario.watchlist, id: \.self) { domain in
                            Text(domain).font(.system(size: 12, design: .monospaced))
                        }
                    }
                    if !scenario.mocks.isEmpty {
                        sectionHeader("Mocks", count: scenario.mocks.count)
                        ForEach(scenario.mocks, id: \.path) { mock in
                            HStack {
                                Text("\(mock.status)")
                                    .font(.caption)
                                    .foregroundStyle(PryTheme.statusColorSwiftUI(mock.status))
                                Text(mock.path)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                    }
                    if !scenario.headers.isEmpty {
                        sectionHeader("Headers", count: scenario.headers.count)
                        ForEach(scenario.headers, id: \.name) { header in
                            Text("\(header.action) \(header.name): \(header.value ?? "")")
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    if !scenario.breakpoints.isEmpty {
                        sectionHeader("Breakpoints", count: scenario.breakpoints.count)
                        ForEach(scenario.breakpoints, id: \.self) { bp in
                            Text(bp).font(.system(size: 12, design: .monospaced))
                        }
                    }
                    if !scenario.blocklist.isEmpty {
                        sectionHeader("Blocklist", count: scenario.blocklist.count)
                        ForEach(scenario.blocklist, id: \.self) { domain in
                            Text(domain).font(.system(size: 12, design: .monospaced))
                        }
                    }
                    if !scenario.statusOverrides.isEmpty {
                        sectionHeader("Status Overrides", count: scenario.statusOverrides.count)
                        ForEach(scenario.statusOverrides, id: \.pattern) { o in
                            Text("\(o.pattern) -> \(o.status)")
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(PryTheme.textSecondary)
                .tracking(1)
            Text("\(count)")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(PryTheme.accent.opacity(0.2))
                .foregroundStyle(PryTheme.accent)
                .clipShape(Capsule())
        }
        .padding(.top, 8)
    }
}
