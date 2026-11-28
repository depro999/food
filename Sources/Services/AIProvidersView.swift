import SwiftUI

/// Secciones de Ajustes para elegir el orden de las IAs y configurar cada una.
struct AIProvidersSection: View {
    @State private var order = AIProvider.savedOrder()
    @State private var refresh = 0   // fuerza a repintar el estado al volver de un detalle

    var body: some View {
        Group {
            Section {
                ForEach(Array(order.enumerated()), id: \.element) { index, p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(p.title)")
                            Text(status(p)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == order.count - 1)
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("IA para fotos · orden de prioridad")
            } footer: {
                Text("Se usa la primera de la lista que tenga clave. Si se queda sin saldo, llega al límite o falla, pasa sola a la siguiente.")
            }

            Section {
                ForEach(AIProvider.allCases) { p in
                    NavigationLink {
                        AIProviderDetailView(provider: p)
                            .onDisappear { refresh += 1 }
                    } label: {
                        HStack {
                            Text(p.title)
                            Spacer()
                            Text(status(p)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Claves y modelos")
            } footer: {
                Text("Las claves se guardan en el Llavero del dispositivo. Para publicar la app en la App Store, lo recomendable es enviar las fotos a tu propio backend y que éste llame a las APIs, en lugar de incluir las claves en el móvil.")
            }
        }
        .id(refresh)
    }

    private func status(_ p: AIProvider) -> String {
        if p.apiKey == nil { return "sin clave" }
        return p.isEnabled ? "lista ✓" : "desactivada"
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        AIProvider.saveOrder(order)
    }
}

struct AIProviderDetailView: View {
    let provider: AIProvider

    @AppStorage private var enabled: Bool
    @AppStorage private var model: String
    @State private var apiKey = ""
    @State private var saved = false

    init(provider: AIProvider) {
        self.provider = provider
        _enabled = AppStorage(wrappedValue: true, provider.enabledKey)
        _model = AppStorage(wrappedValue: provider.defaultModel, provider.modelKey)
    }

    private var note: String {
        switch provider {
        case .claude:
            return "Necesitas una API key de console.anthropic.com con saldo. Una suscripción de Claude.ai no incluye API."
        case .openai:
            return "Necesitas una API key de platform.openai.com con saldo. Una suscripción de ChatGPT Plus no incluye API."
        case .gemini:
            return "Google AI Studio suele ofrecer una capa gratuita con límites, útil como primera opción o de reserva."
        case .deepseek:
            return "El modelo «deepseek-flash» admite imágenes. Si cambias a un modelo sin visión, fallará y se pasará a la siguiente IA."
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Usar esta IA", isOn: $enabled)
            }

            Section {
                SecureField("API key (\(provider.keyHint))", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(saved ? "Guardada ✓" : "Guardar clave") {
                    Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                 for: provider.keychainKey)
                    saved = true
                }
                Link("Conseguir una API key", destination: provider.consoleURL)
            } header: {
                Text("Clave")
            } footer: {
                Text(note)
            }

            Section {
                TextField("Modelo", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Restaurar modelo por defecto") { model = provider.defaultModel }
                    .font(.footnote)
            } header: {
                Text("Modelo")
            } footer: {
                Text("Debe admitir imágenes. Por defecto: \(provider.defaultModel).")
            }
        }
        .navigationTitle(provider.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { apiKey = Keychain.get(provider.keychainKey) ?? "" }
        .onChange(of: apiKey) { _, _ in saved = false }
    }
}
