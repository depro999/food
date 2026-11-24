import SwiftUI
import SwiftData

// MARK: - Lista de recetas

struct RecipesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var editing: Recipe?
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView("Sin recetas",
                        systemImage: "book.closed",
                        description: Text("Crea una receta y hazla repetir los días que quieras (por ejemplo, los lunes y miércoles). También puedes guardar una comida del diario como receta."))
                } else {
                    List {
                        ForEach(recipes) { r in
                            Button { editing = r } label: { row(r) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        RecipeScheduler.add(r, to: Date(), context: context)
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    } label: { Label("Añadir hoy", systemImage: "plus") }
                                    .tint(.green)
                                }
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(recipes[i]) }
                        }
                    }
                }
            }
            .navigationTitle("Recetas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(item: $editing) { RecipeEditorView(recipe: $0) }
            .sheet(isPresented: $showNew) { RecipeEditorView() }
        }
    }

    private func row(_ r: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label(r.name, systemImage: r.meal.icon).font(.headline)
                Spacer()
                Text("\(fmt(r.total.kcal)) kcal").monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if !r.weekdays.isEmpty { Image(systemName: "repeat").font(.caption) }
                Text(Weekday.summary(r.weekdays))
                if !r.weekdays.isEmpty { Text(r.autoAdd ? "· automática" : "· con aviso") }
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("\(r.items.count) ingredientes · P \(fmt(r.total.protein)) · C \(fmt(r.total.carbs)) · G \(fmt(r.total.fat))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Editor

/// Datos para crear una receta a partir de una comida del diario.
struct RecipeDraft: Identifiable {
    let id = UUID()
    let meal: MealType
    let items: [RecipeItem]
}

struct RecipeEditorView: View {
    let recipe: Recipe?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var meal: MealType
    @State private var items: [RecipeItem]
    @State private var weekdays: Set<Int>
    @State private var autoAdd: Bool
    @State private var showPicker = false

    init(recipe: Recipe? = nil, meal: MealType = .lunch, items: [RecipeItem] = []) {
        self.recipe = recipe
        _name = State(initialValue: recipe?.name ?? "")
        _meal = State(initialValue: recipe?.meal ?? meal)
        _items = State(initialValue: recipe?.items ?? items)
        _weekdays = State(initialValue: Set(recipe?.weekdays ?? []))
        _autoAdd = State(initialValue: recipe?.autoAdd ?? true)
    }

    private var total: Macros { items.reduce(.zero) { $0 + $1.macros } }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !items.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (ej: Desayuno de lunes)", text: $name)
                    Picker("Comida", selection: $meal) {
                        ForEach(MealType.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).lineLimit(1)
                            Stepper(value: gramsBinding(item.id), in: 5...3000, step: 10) {
                                Text("\(fmt(item.grams)) g · \(fmt(item.macros.kcal)) kcal")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button { showPicker = true } label: {
                        Label("Añadir alimento", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Ingredientes")
                } footer: {
                    if !items.isEmpty {
                        Text("Total: \(fmt(total.kcal)) kcal · P \(fmt(total.protein)) g · C \(fmt(total.carbs)) g · G \(fmt(total.fat)) g")
                    }
                }

                Section {
                    HStack(spacing: 6) {
                        ForEach(Weekday.ordered, id: \.self) { d in
                            let on = weekdays.contains(d)
                            Button {
                                if on { weekdays.remove(d) } else { weekdays.insert(d) }
                            } label: {
                                Text(Weekday.initial(d))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 36, height: 36)
                                    .background(on ? Color.accentColor : Color(.secondarySystemFill), in: Circle())
                                    .foregroundStyle(on ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    HStack {
                        Button("L–V") { weekdays = Weekday.weekdays }
                        Spacer()
                        Button("Fin de semana") { weekdays = Weekday.weekend }
                        Spacer()
                        Button("Todos") { weekdays = Set(1...7) }
                        Spacer()
                        Button("Ninguno") { weekdays = [] }
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)

                    if !weekdays.isEmpty {
                        Toggle("Añadir automáticamente", isOn: $autoAdd)
                    }
                } header: {
                    Text("Repetir")
                } footer: {
                    if weekdays.isEmpty {
                        Text("Sin días seleccionados: la receta solo se añade cuando tú quieras.")
                    } else if autoAdd {
                        Text("Se añadirá sola al diario esos días al abrir la app. Puedes borrarla del día si no la comes.")
                    } else {
                        Text("Esos días aparecerá en «Hoy» como pendiente, para añadirla con un toque.")
                    }
                }
            }
            .navigationTitle(recipe == nil ? "Nueva receta" : "Editar receta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }.disabled(!canSave)
                }
            }
            .sheet(isPresented: $showPicker) {
                RecipeItemPicker { items.append($0) }
            }
        }
    }

    private func gramsBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { items.first { $0.id == id }?.grams ?? 0 },
            set: { new in
                if let i = items.firstIndex(where: { $0.id == id }) { items[i].rescale(to: new) }
            })
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let days = Weekday.ordered.filter(weekdays.contains)
        if let r = recipe {
            r.name = n; r.meal = meal; r.items = items
            r.weekdays = days; r.autoAdd = autoAdd
        } else {
            context.insert(Recipe(name: n, meal: meal, items: items, weekdays: days, autoAdd: autoAdd))
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Selector de ingredientes

struct RecipeItemPicker: View {
    let onPick: (RecipeItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = OpenFoodFactsService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ManualItemForm { onPick($0); dismiss() }
                    } label: {
                        Label("Añadir manualmente", systemImage: "square.and.pencil")
                    }
                }
                Section("Resultados") {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if results.isEmpty {
                        Text(query.isEmpty ? "Busca un alimento por nombre o marca." : "Sin resultados.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { item in
                        NavigationLink {
                            ItemGramsView(food: item) { onPick($0); dismiss() }
                        } label: { FoodRow(item: item) }
                    }
                }
            }
            .navigationTitle("Añadir ingrediente")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Buscar alimento")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { results = try await service.search(q) }
        catch { errorMessage = "No se pudo conectar con la base de datos. Revisa tu conexión." }
    }
}

private struct ItemGramsView: View {
    let food: FoodItem
    let onAdd: (RecipeItem) -> Void
    @State private var gramsText: String

    init(food: FoodItem, onAdd: @escaping (RecipeItem) -> Void) {
        self.food = food
        self.onAdd = onAdd
        _gramsText = State(initialValue: fmt(food.servingGrams ?? 100))
    }

    private var grams: Double { parseNumber(gramsText) }
    private var macros: Macros { food.macros(for: grams) }

    var body: some View {
        Form {
            Section {
                Text(food.name).font(.headline)
                if let b = food.brand, !b.isEmpty { Text(b).foregroundStyle(.secondary) }
            }
            Section("Cantidad") {
                HStack {
                    TextField("Gramos", text: $gramsText).keyboardType(.decimalPad)
                    Text("g").foregroundStyle(.secondary)
                }
            }
            Section("Aporte") {
                LabeledContent("Calorías", value: "\(fmt(macros.kcal)) kcal")
                LabeledContent("Proteína", value: "\(fmt(macros.protein, decimals: 1)) g")
                LabeledContent("Carbohidratos", value: "\(fmt(macros.carbs, decimals: 1)) g")
                LabeledContent("Grasas", value: "\(fmt(macros.fat, decimals: 1)) g")
            }
            Section {
                Button {
                    onAdd(RecipeItem(name: food.name, brand: food.brand, grams: grams, macros: macros))
                } label: { Text("Añadir a la receta").frame(maxWidth: .infinity).bold() }
                .disabled(grams <= 0)
            }
        }
        .navigationTitle("Cantidad")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ManualItemForm: View {
    let onSave: (RecipeItem) -> Void
    @State private var name = ""
    @State private var grams = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        Form {
            Section("Alimento") {
                TextField("Nombre", text: $name)
                field("Gramos", $grams, "g")
            }
            Section("Macros totales de esa cantidad") {
                field("Calorías", $kcal, "kcal")
                field("Proteína", $protein, "g")
                field("Carbohidratos", $carbs, "g")
                field("Grasas", $fat, "g")
            }
            Section {
                Button {
                    onSave(RecipeItem(
                        name: name.trimmingCharacters(in: .whitespaces), brand: nil,
                        grams: parseNumber(grams),
                        macros: Macros(kcal: parseNumber(kcal), protein: parseNumber(protein),
                                       carbs: parseNumber(carbs), fat: parseNumber(fat))))
                } label: { Text("Añadir a la receta").frame(maxWidth: .infinity).bold() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parseNumber(grams) <= 0)
            }
        }
        .navigationTitle("Manual")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ label: String, _ text: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(label)
            TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
