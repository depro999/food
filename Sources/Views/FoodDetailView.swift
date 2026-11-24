import SwiftUI
import SwiftData

struct FoodDetailView: View {
    let food: FoodItem
    let date: Date
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var gramsText: String
    @State private var meal: MealType

    init(food: FoodItem, date: Date, initialMeal: MealType, onSaved: @escaping () -> Void) {
        self.food = food
        self.date = date
        self.onSaved = onSaved
        _gramsText = State(initialValue: fmt(food.servingGrams ?? 100))
        _meal = State(initialValue: initialMeal)
    }

    private var grams: Double { Double(gramsText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var macros: Macros { food.macros(for: grams) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name).font(.headline)
                    if let b = food.brand, !b.isEmpty { Text(b).foregroundStyle(.secondary) }
                }
            }

            Section("Cantidad") {
                HStack {
                    TextField("Gramos", text: $gramsText).keyboardType(.decimalPad)
                    Text("g").foregroundStyle(.secondary)
                }
                Picker("Comida", selection: $meal) {
                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Aporte nutricional") {
                row("Calorías", "\(fmt(macros.kcal)) kcal", .orange)
                row("Proteína", "\(fmt(macros.protein, decimals: 1)) g", .red)
                row("Carbohidratos", "\(fmt(macros.carbs, decimals: 1)) g", .blue)
                row("Grasas", "\(fmt(macros.fat, decimals: 1)) g", .yellow)
            }

            Section {
                Button {
                    context.insert(FoodEntry(
                        date: entryTimestamp(for: date), meal: meal, name: food.name,
                        brand: food.brand, grams: grams, macros: macros,
                        source: food.barcode == nil ? "search" : "barcode"))
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onSaved()
                } label: {
                    Text("Añadir al diario").frame(maxWidth: .infinity).bold()
                }
                .disabled(grams <= 0)
            }
        }
        .navigationTitle("Detalle")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
