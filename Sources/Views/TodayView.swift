import SwiftUI
import SwiftData

struct AddTarget: Identifiable {
    let id = UUID()
    let meal: MealType
}

struct TodayView: View {
    @State private var date = Date()
    @State private var addTarget: AddTarget?

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Hoy" }
        if cal.isDateInYesterday(date) { return "Ayer" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func shift(_ days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    var body: some View {
        NavigationStack {
            DayContent(date: date) { meal in addTarget = AddTarget(meal: meal) }
                .id(Calendar.current.startOfDay(for: date))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack {
                            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                                .disabled(Calendar.current.isDateInToday(date))
                            Button { addTarget = AddTarget(meal: suggestedMeal) } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                    }
                }
                .sheet(item: $addTarget) { target in
                    AddFoodView(date: date, meal: target.meal)
                }
        }
    }

    private var suggestedMeal: MealType {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: .breakfast
        case 11..<16: .lunch
        case 16..<19: .snack
        default: .dinner
        }
    }
}

struct DayContent: View {
    @Environment(\.modelContext) private var context
    @AppStorage("goalKcal") private var goalKcal = 2200.0
    @AppStorage("goalProtein") private var goalProtein = 150.0
    @AppStorage("goalCarbs") private var goalCarbs = 250.0
    @AppStorage("goalFat") private var goalFat = 70.0

    @Query private var entries: [FoodEntry]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var draft: RecipeDraft?
    let date: Date
    let onAdd: (MealType) -> Void

    init(date: Date, onAdd: @escaping (MealType) -> Void) {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= start && $0.date < end },
                         sort: \.date)
        self.date = date
        self.onAdd = onAdd
    }

    /// Recetas recurrentes de hoy que no se añaden solas y siguen pendientes.
    private var pending: [Recipe] {
        guard Calendar.current.isDateInToday(date) else { return [] }
        return recipes.filter { !$0.autoAdd && !$0.items.isEmpty && RecipeScheduler.isDue($0, on: date) }
    }

    private var total: Macros { entries.reduce(.zero) { $0 + $1.macros } }

    var body: some View {
        List {
            Section {
                SummaryCard(total: total, goalKcal: goalKcal, goalProtein: goalProtein,
                            goalCarbs: goalCarbs, goalFat: goalFat)
            }

            if !pending.isEmpty {
                Section("Planificado para hoy") {
                    ForEach(pending) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(r.name, systemImage: r.meal.icon).lineLimit(1)
                                Text("\(r.meal.title) · \(fmt(r.total.kcal)) kcal")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Añadir") {
                                RecipeScheduler.add(r, to: date, context: context)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .swipeActions {
                            Button("Omitir") { RecipeScheduler.skipToday(r) }.tint(.gray)
                        }
                    }
                }
            }

            ForEach(MealType.allCases) { meal in
                let items = entries.filter { $0.meal == meal }
                Section {
                    ForEach(items) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(e.name).lineLimit(1)
                                if e.source == "ai" {
                                    Image(systemName: "sparkles").font(.caption).foregroundStyle(.purple)
                                } else if e.source == "recipe" {
                                    Image(systemName: "repeat").font(.caption).foregroundStyle(.green)
                                }
                                Spacer()
                                Text("\(fmt(e.kcal)) kcal").monospacedDigit()
                            }
                            Text("\(fmt(e.grams)) g · P \(fmt(e.protein)) · C \(fmt(e.carbs)) · G \(fmt(e.fat))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(items[i]) }
                    }
                    Button { onAdd(meal) } label: {
                        Label("Añadir", systemImage: "plus.circle")
                    }
                } header: {
                    HStack {
                        Label(meal.title, systemImage: meal.icon)
                        Spacer()
                        Text("\(fmt(items.reduce(0) { $0 + $1.kcal })) kcal")
                        if !items.isEmpty {
                            Menu {
                                Button {
                                    draft = RecipeDraft(meal: meal, items: items.map {
                                        RecipeItem(name: $0.name, brand: $0.brand, grams: $0.grams, macros: $0.macros)
                                    })
                                } label: { Label("Guardar como receta / repetir", systemImage: "repeat") }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $draft) { RecipeEditorView(meal: $0.meal, items: $0.items) }
    }
}

struct SummaryCard: View {
    let total: Macros
    let goalKcal, goalProtein, goalCarbs, goalFat: Double

    private var progress: Double { goalKcal > 0 ? min(total.kcal / goalKcal, 1) : 0 }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.orange.opacity(0.2), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(total.kcal > goalKcal ? Color.red : Color.orange,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: progress)
                VStack(spacing: 0) {
                    Text(fmt(total.kcal)).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(goalKcal - total.kcal >= 0
                         ? "quedan \(fmt(goalKcal - total.kcal)) kcal"
                         : "te pasas \(fmt(total.kcal - goalKcal)) kcal")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)

            VStack(spacing: 10) {
                MacroBar(label: "Proteína", value: total.protein, goal: goalProtein, color: .red)
                MacroBar(label: "Carbohidratos", value: total.carbs, goal: goalCarbs, color: .blue)
                MacroBar(label: "Grasas", value: total.fat, goal: goalFat, color: .yellow)
            }
        }
        .padding(.vertical, 8)
    }
}

struct MacroBar: View {
    let label: String
    let value: Double
    let goal: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(fmt(value)) / \(fmt(goal)) g").font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: goal > 0 ? min(value / goal, 1) : 0).tint(color)
        }
    }
}
