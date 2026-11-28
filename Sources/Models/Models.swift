import Foundation
import SwiftData

// MARK: - Macros

struct Macros: Equatable {
    var kcal = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0

    static let zero = Macros()

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein,
               carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
    }
}

func fmt(_ v: Double, decimals: Int = 0) -> String {
    String(format: "%.\(decimals)f", v)
}

// MARK: - Comidas del día

enum MealType: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Desayuno"
        case .lunch: "Comida"
        case .dinner: "Cena"
        case .snack: "Snacks"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }
}

// MARK: - Alimento (resultado de búsqueda / escaneo)

struct FoodItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var brand: String?
    var kcalPer100: Double
    var proteinPer100: Double
    var carbsPer100: Double
    var fatPer100: Double
    var servingGrams: Double?
    var barcode: String?
    var imageURL: URL?
    var microsPer100: Micros = [:]   // gramos por 100 g

    func micros(for grams: Double) -> Micros {
        microsPer100.mapValues { $0 * grams / 100 }
    }

    func macros(for grams: Double) -> Macros {
        let f = grams / 100
        return Macros(kcal: kcalPer100 * f, protein: proteinPer100 * f,
                      carbs: carbsPer100 * f, fat: fatPer100 * f)
    }
}

// MARK: - Registro guardado (SwiftData)

@Model
final class FoodEntry {
    var id: UUID
    var date: Date
    var mealRaw: String
    var name: String
    var brand: String?
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var source: String   // "barcode", "search", "ai", "recipe"
    var microsData: Data?            // micronutrientes (JSON, en gramos)
    var healthSynced: Bool = false   // ya enviado a Apple Salud

    init(date: Date, meal: MealType, name: String, brand: String?, grams: Double,
         macros: Macros, source: String, micros: Micros = [:]) {
        self.id = UUID()
        self.date = date
        self.mealRaw = meal.rawValue
        self.name = name
        self.brand = brand
        self.grams = grams
        self.kcal = macros.kcal
        self.protein = macros.protein
        self.carbs = macros.carbs
        self.fat = macros.fat
        self.source = source
        self.microsData = micros.isEmpty ? nil : try? JSONEncoder().encode(micros)
        self.healthSynced = false
    }

    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    var micros: Micros {
        microsData.flatMap { try? JSONDecoder().decode(Micros.self, from: $0) } ?? [:]
    }
}

/// Fecha con la que se guarda un registro al añadirlo a un día concreto.
func entryTimestamp(for day: Date) -> Date {
    let cal = Calendar.current
    if cal.isDateInToday(day) { return Date() }
    return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
}

// MARK: - Recetas / comidas recurrentes

/// Ingrediente de una receta. Guarda los macros TOTALES para los gramos indicados.
struct RecipeItem: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var brand: String?
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var microsData: Data?

    init(name: String, brand: String?, grams: Double, macros: Macros, micros: Micros = [:]) {
        self.id = UUID()
        self.name = name
        self.brand = brand
        self.grams = grams
        self.kcal = macros.kcal
        self.protein = macros.protein
        self.carbs = macros.carbs
        self.fat = macros.fat
        self.microsData = micros.isEmpty ? nil : try? JSONEncoder().encode(micros)
    }

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    var micros: Micros {
        get { microsData.flatMap { try? JSONDecoder().decode(Micros.self, from: $0) } ?? [:] }
        set { microsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    /// Cambia los gramos escalando los macros proporcionalmente.
    mutating func rescale(to newGrams: Double) {
        guard grams > 0, newGrams > 0 else { grams = max(newGrams, 0); return }
        let f = newGrams / grams
        kcal *= f; protein *= f; carbs *= f; fat *= f
        micros = micros.mapValues { $0 * f }
        grams = newGrams
    }
}

/// Receta guardada. Si tiene `weekdays`, se repite esos días de la semana.
@Model
final class Recipe {
    var id: UUID
    var name: String
    var mealRaw: String
    var items: [RecipeItem]
    var weekdays: [Int]          // Calendar.weekday: 1 = domingo … 7 = sábado
    var autoAdd: Bool            // true: se añade sola al diario; false: aparece como pendiente
    var lastAppliedDay: Date?    // último día en que se añadió/omitió (evita duplicados)
    var createdAt: Date

    init(name: String, meal: MealType, items: [RecipeItem], weekdays: [Int], autoAdd: Bool) {
        self.id = UUID()
        self.name = name
        self.mealRaw = meal.rawValue
        self.items = items
        self.weekdays = weekdays
        self.autoAdd = autoAdd
        self.lastAppliedDay = nil
        self.createdAt = Date()
    }

    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .lunch }
        set { mealRaw = newValue.rawValue }
    }

    var total: Macros { items.reduce(.zero) { $0 + $1.macros } }
}

enum Weekday {
    /// Orden español: lunes primero (valores de Calendar.weekday).
    static let ordered = [2, 3, 4, 5, 6, 7, 1]
    static let weekdays = Set([2, 3, 4, 5, 6])
    static let weekend = Set([7, 1])

    static func short(_ d: Int) -> String { ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"][d - 1] }
    static func initial(_ d: Int) -> String { ["D", "L", "M", "X", "J", "V", "S"][d - 1] }

    static func summary(_ days: [Int]) -> String {
        let set = Set(days)
        if set.isEmpty { return "Sin repetición" }
        if set.count == 7 { return "Todos los días" }
        if set == weekdays { return "Lunes a viernes" }
        if set == weekend { return "Fines de semana" }
        return ordered.filter(set.contains).map(short).joined(separator: ", ")
    }
}

func parseNumber(_ s: String) -> Double {
    Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
}
