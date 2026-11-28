import SwiftUI
import SwiftData

struct FoodDetailView: View {
    let food: FoodItem
    let date: Date
    /// Si no es nil, el alimento se devuelve a una receta en vez de guardarse en el diario.
    let onPick: ((RecipeItem) -> Void)?
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var gramsText: String
    @State private var meal: MealType

    init(food: FoodItem, date: Date, initialMeal: MealType,
         onPick: ((RecipeItem) -> Void)? = nil, onSaved: @escaping () -> Void) {
        self.food = food
        self.date = date
        self.onPick = onPick
        self.onSaved = onSaved
        _gramsText = State(initialValue: fmt(food.servingGrams ?? 100))
        _meal = State(initialValue: initialMeal)
    }

    private var grams: Double { parseNumber(gramsText) }
    private var macros: Macros { food.macros(for: grams) }
    private var micros: Micros { food.micros(for: grams) }

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
                if onPick == nil {
                    Picker("Comida", selection: $meal) {
                        ForEach(MealType.allCases) { Text($0.title).tag($0) }
                    }
                }
            }

            Section("Aporte nutricional") {
                row("Calorías", "\(fmt(macros.kcal)) kcal", .orange)
                row("Proteína", "\(fmt(macros.protein, decimals: 1)) g", .red)
                row("Carbohidratos", "\(fmt(macros.carbs, decimals: 1)) g", .blue)
                row("Grasas", "\(fmt(macros.fat, decimals: 1)) g", .yellow)
            }

            Section {
                DisclosureGroup("Micronutrientes") {
                    let present = Nutrient.allCases.filter { (micros[$0.rawValue] ?? 0) > 0 }
                    if present.isEmpty {
                        Text("Sin datos en Open Food Facts para este producto.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(present) { n in
                        LabeledContent(n.title, value: n.format(micros[n.rawValue] ?? 0))
                    }
                }
            }

            Section {
                Button {
                    if let onPick {
                        onPick(RecipeItem(name: food.name, brand: food.brand, grams: grams,
                                          macros: macros, micros: micros))
                    } else {
                        context.insert(FoodEntry(
                            date: entryTimestamp(for: date), meal: meal, name: food.name,
                            brand: food.brand, grams: grams, macros: macros,
                            source: food.barcode == nil ? "search" : "barcode",
                            micros: micros))
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onSaved()
                } label: {
                    Text(onPick == nil ? "Añadir al diario" : "Añadir a la receta")
                        .frame(maxWidth: .infinity).bold()
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
