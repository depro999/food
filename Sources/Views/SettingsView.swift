import SwiftUI

struct SettingsView: View {
    @AppStorage("goalKcal") private var goalKcal = 2200.0
    @AppStorage("goalProtein") private var goalProtein = 150.0
    @AppStorage("goalCarbs") private var goalCarbs = 250.0
    @AppStorage("goalFat") private var goalFat = 70.0
    @AppStorage("aiModel") private var aiModel = AIFoodRecognizer.defaultModel

    @State private var apiKey = ""
    @State private var saved = false
    @AppStorage("healthSync") private var healthSync = false
    @State private var healthMessage: String?

    private var kcalFromMacros: Double { goalProtein * 4 + goalCarbs * 4 + goalFat * 9 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Objetivos diarios") {
                    goalRow("Calorías", value: $goalKcal, unit: "kcal", step: 50)
                    goalRow("Proteína", value: $goalProtein, unit: "g", step: 5)
                    goalRow("Carbohidratos", value: $goalCarbs, unit: "g", step: 5)
                    goalRow("Grasas", value: $goalFat, unit: "g", step: 5)
                    Text("Tus macros suman \(fmt(kcalFromMacros)) kcal (4·P + 4·C + 9·G).")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Ajustar calorías a los macros") { goalKcal = kcalFromMacros }
                        .font(.footnote)
                }

                Section {
                    SecureField("API key de Anthropic (sk-ant-…)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Modelo", text: $aiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(saved ? "Guardada ✓" : "Guardar clave") {
                        Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                     for: AIFoodRecognizer.keychainKey)
                        saved = true
                    }
                } header: {
                    Text("IA para fotos de comida")
                } footer: {
                    Text("La clave se guarda en el Llavero del dispositivo. Para publicar la app en la App Store, lo recomendable es enviar las fotos a tu propio backend y que éste llame a la API, en lugar de incluir la clave en el móvil.")
                }

                Section {
                    Toggle("Guardar en Apple Salud", isOn: $healthSync)
                        .disabled(!HealthSync.isAvailable)
                    if !HealthSync.isAvailable {
                        Text("No disponible en esta compilación: Apple Salud exige firmar la app con la capacidad HealthKit (cuenta de Apple Developer de pago).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let healthMessage {
                        Text(healthMessage).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Apple Salud")
                } footer: {
                    Text("Guarda calorías, macros y micronutrientes (fibra, vitaminas, minerales…) de cada alimento en Salud › Nutrición. Al activarlo también se envían los registros que ya tienes. Si borras un registro, se borra también de Salud. Los micronutrientes vienen de Open Food Facts o, en las fotos, de la estimación de la IA.")
                }

                Section("Datos") {
                    LabeledContent("Base de datos de alimentos", value: "Open Food Facts")
                    Link("Contribuir a Open Food Facts",
                         destination: URL(string: "https://world.openfoodfacts.org")!)
                }
            }
            .navigationTitle("Ajustes")
            .onAppear {
                apiKey = Keychain.get(AIFoodRecognizer.keychainKey) ?? ""
                if !HealthSync.isAvailable { healthSync = false }
            }
            .onChange(of: apiKey) { _, _ in saved = false }
            .onChange(of: healthSync) { _, on in
                guard on else { healthMessage = nil; return }
                Task {
                    healthMessage = await HealthSync.shared.requestAuthorization()
                    if !HealthSync.isAvailable { healthSync = false }
                }
            }
        }
    }

    private func goalRow(_ title: String, value: Binding<Double>, unit: String, step: Double) -> some View {
        Stepper(value: value, in: 0...10000, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(fmt(value.wrappedValue)) \(unit)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
