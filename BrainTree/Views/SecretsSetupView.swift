import SwiftUI

struct SecretsSetupView: View {
    @State private var values: [SecretsKey: String] = {
        Dictionary(uniqueKeysWithValues: SecretsKey.allCases.map { ($0, KeychainClient.load($0) ?? "") })
    }()
    @State private var saved = false
    @State private var confirmErase = false
    @Environment(\.dismiss) private var dismiss

    private var allFilled: Bool { !values.values.contains(where: \.isEmpty) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("These keys are stored in the device Keychain and never leave your device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Supabase") {
                    LabeledField(key: .supabaseURL, values: $values)
                    LabeledField(key: .supabaseKey, values: $values)
                }

                Section("MCP Server") {
                    LabeledField(key: .mcpAccessKey, values: $values)
                }

                Section("Anthropic") {
                    LabeledField(key: .anthropicKey, values: $values)
                }
            }
            .navigationTitle("API Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!allFilled)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Erase All Settings", role: .destructive) {
                        confirmErase = true
                    }
                    .foregroundStyle(.red)
                }
            }
            .overlay {
                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: saved)
            .confirmationDialog("Erase all API keys?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase All", role: .destructive) {
                    let defaults = UserDefaults(suiteName: "group.com.dyerlab.openbrain")
                    for key in SecretsKey.allCases {
                        KeychainClient.delete(key)
                        defaults?.removeObject(forKey: key.rawValue)
                    }
                    values = Dictionary(uniqueKeysWithValues: SecretsKey.allCases.map { ($0, "") })
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func save() {
        let defaults = UserDefaults(suiteName: "group.com.dyerlab.openbrain")
        for key in SecretsKey.allCases {
            if let v = values[key], !v.isEmpty {
                KeychainClient.save(v, for: key)
                if key == .supabaseURL || key == .supabaseKey {
                    defaults?.set(v, forKey: key.rawValue)
                }
            }
        }
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
    }
}

private struct LabeledField: View {
    let key: SecretsKey
    @Binding var values: [SecretsKey: String]

    var body: some View {
        TextField(key.displayName, text: binding)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(key == .supabaseURL ? .URL : .default)
    }

    private var binding: Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }
}
