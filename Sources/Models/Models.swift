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
    var source: String   // "barcode", "search", "ai"

    init(date: Date, meal: MealType, name: String, brand: String?, grams: Double,
         macros: Macros, source: String) {
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
    }

    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}

/// Fecha con la que se guarda un registro al añadirlo a un día concreto.
func entryTimestamp(for day: Date) -> Date {
    let cal = Calendar.current
    if cal.isDateInToday(day) { return Date() }
    return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
}
