import Foundation
import SwiftData

enum RecipeScheduler {
    /// ¿Toca esta receta ese día y aún no se ha aplicado?
    static func isDue(_ r: Recipe, on day: Date) -> Bool {
        let cal = Calendar.current
        guard r.weekdays.contains(cal.component(.weekday, from: day)) else { return false }
        if let last = r.lastAppliedDay, cal.isDate(last, inSameDayAs: day) { return false }
        return true
    }

    /// Inserta todos los ingredientes de la receta en el diario.
    static func add(_ r: Recipe, to day: Date, meal: MealType? = nil, context: ModelContext) {
        let stamp = entryTimestamp(for: day)
        for it in r.items {
            context.insert(FoodEntry(date: stamp, meal: meal ?? r.meal, name: it.name, brand: it.brand,
                                     grams: it.grams, macros: it.macros, source: "recipe"))
        }
        if Calendar.current.isDateInToday(day) { r.lastAppliedDay = Date() }
    }

    /// Marca la receta como resuelta hoy sin añadirla (omitir).
    static func skipToday(_ r: Recipe) { r.lastAppliedDay = Date() }

    /// Añade al diario de HOY las recetas recurrentes con `autoAdd` que toquen.
    static func applyDue(context: ModelContext) {
        guard let recipes = try? context.fetch(FetchDescriptor<Recipe>()) else { return }
        let today = Date()
        for r in recipes where r.autoAdd && !r.items.isEmpty && isDue(r, on: today) {
            add(r, to: today, context: context)
        }
    }
}
