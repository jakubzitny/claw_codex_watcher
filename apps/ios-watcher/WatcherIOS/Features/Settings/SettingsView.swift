import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: WatcherStore

    @State private var serverURL = ""
    @State private var authToken = ""
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Watcher Server") {
                    TextField("http://127.0.0.1:18000", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("settings.serverURL")

                    SecureField("Optional watcher auth token", text: $authToken)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("settings.authToken")

                    Button("Save and Reconnect") {
                        Task { @MainActor in
                            await saveConfiguration()
                        }
                    }
                    .accessibilityIdentifier("settings.save")
                }

                Section("Connection") {
                    LabeledContent("Mode", value: store.connectionState.rawValue.capitalized)
                    if let lastRefreshAt = store.lastRefreshAt {
                        LabeledContent("Last Refresh", value: relativeDate(from: lastRefreshAt))
                    } else {
                        LabeledContent("Last Refresh", value: "Not yet")
                    }
                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let saveMessage {
                    Section {
                        Text(saveMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            hydrateFields(from: store.configuration)
        }
        .onChange(of: store.configuration) { _, newValue in
            hydrateFields(from: newValue)
        }
    }

    @MainActor
    private func saveConfiguration() async {
        do {
            try await store.saveConfiguration(serverURLRaw: serverURL, authToken: authToken)
            saveMessage = "Saved. Reconnected using \(store.configuration.serverURL.absoluteString)."
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func hydrateFields(from configuration: WatcherConfiguration) {
        serverURL = configuration.serverURL.absoluteString
        authToken = configuration.authToken ?? ""
    }

    private func relativeDate(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
