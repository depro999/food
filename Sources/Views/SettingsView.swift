import SwiftUI

struct SettingsView: View {
    @AppStorage("goalKcal") private var goalKcal = 2200.0
    @AppStorage("goalProtein") private var goalProtein = 150.0
    @AppStorage("goalCarbs") private var goalCarbs = 250.0
    @AppStorage("goalFat") private var goalFat = 70.0


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

                AIProvidersSection()

                Section("Apple Salud") {
                    NavigationLink {
                        ShortcutsHelpView()
                    } label: {
                        Label("Pasar a Apple Salud con Atajos", systemImage: "heart.text.square")
                    }
                }

                Section("Datos") {
                    LabeledContent("Base de datos de alimentos", value: "Open Food Facts")
                    Link("Contribuir a Open Food Facts",
                         destination: URL(string: "https://world.openfoodfacts.org")!)
                }
            }
            .navigationTitle("Ajustes")
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
