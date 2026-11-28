import AppIntents
import SwiftData
import UniformTypeIdentifiers

// MARK: - Parámetros

enum MealFilter: String, AppEnum {
    case all, breakfast, lunch, dinner, snack

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Comida"
    static let caseDisplayRepresentations: [MealFilter: DisplayRepresentation] = [
        .all: "Todo el día",
        .breakfast: "Desayuno",
        .lunch: "Comida",
        .dinner: "Cena",
        .snack: "Snacks"
    ]
}

/// Nutrientes que se pueden pedir. Los valores se devuelven en kcal (calorías), g (macros)
/// o en la unidad natural del micronutriente (g, mg o µg).
enum NutrientOption: String, AppEnum {
    case calories, protein, carbs, fat
    case fiber, sugars, saturatedFat, monounsaturatedFat, polyunsaturatedFat
    case cholesterol, sodium, potassium, calcium, iron, magnesium, zinc, phosphorus
    case copper, manganese, selenium, iodine, chromium, molybdenum, chloride
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminK
    case thiamin, riboflavin, niacin, vitaminB6, folate, vitaminB12, biotin, pantothenicAcid
    case caffeine

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Nutriente"
    // Debe ser un diccionario literal: App Intents lo lee en tiempo de compilación.
    static let caseDisplayRepresentations: [NutrientOption: DisplayRepresentation] = [
        .calories: "Calorías (kcal)",
        .protein: "Proteína (g)",
        .carbs: "Carbohidratos (g)",
        .fat: "Grasas (g)",
        .fiber: "Fibra (g)",
        .sugars: "Azúcares (g)",
        .saturatedFat: "Grasa saturada (g)",
        .monounsaturatedFat: "Grasa monoinsaturada (g)",
        .polyunsaturatedFat: "Grasa poliinsaturada (g)",
        .cholesterol: "Colesterol (mg)",
        .sodium: "Sodio (mg)",
        .potassium: "Potasio (mg)",
        .calcium: "Calcio (mg)",
        .iron: "Hierro (mg)",
        .magnesium: "Magnesio (mg)",
        .zinc: "Zinc (mg)",
        .phosphorus: "Fósforo (mg)",
        .copper: "Cobre (mg)",
        .manganese: "Manganeso (mg)",
        .selenium: "Selenio (µg)",
        .iodine: "Yodo (µg)",
        .chromium: "Cromo (µg)",
        .molybdenum: "Molibdeno (µg)",
        .chloride: "Cloruro (mg)",
        .vitaminA: "Vitamina A (µg)",
        .vitaminC: "Vitamina C (mg)",
        .vitaminD: "Vitamina D (µg)",
        .vitaminE: "Vitamina E (mg)",
        .vitaminK: "Vitamina K (µg)",
        .thiamin: "B1 tiamina (mg)",
        .riboflavin: "B2 riboflavina (mg)",
        .niacin: "B3 niacina (mg)",
        .vitaminB6: "Vitamina B6 (mg)",
        .folate: "B9 folato (µg)",
        .vitaminB12: "Vitamina B12 (µg)",
        .biotin: "Biotina (µg)",
        .pantothenicAcid: "B5 ácido pantoténico (mg)",
        .caffeine: "Cafeína (mg)"
    ]
}

// MARK: - Lógica compartida

@MainActor
enum NutritionExport {
    static func startOfDay(_ day: Date?) -> Date {
        Calendar.current.startOfDay(for: day ?? Date())
    }

    static func entries(on day: Date?, meal: MealFilter = .all) throws -> [FoodEntry] {
        let start = startOfDay(day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)])
        let all = try Persistence.container.mainContext.fetch(descriptor)
        return meal == .all ? all : all.filter { $0.mealRaw == meal.rawValue }
    }

    static func total(_ option: NutrientOption, in entries: [FoodEntry]) -> Double {
        let value: Double
        switch option {
        case .calories: value = entries.reduce(0) { $0 + $1.kcal }
        case .protein: value = entries.reduce(0) { $0 + $1.protein }
        case .carbs: value = entries.reduce(0) { $0 + $1.carbs }
        case .fat: value = entries.reduce(0) { $0 + $1.fat }
        default:
            guard let n = Nutrient(rawValue: option.rawValue) else { return 0 }
            let grams = entries.reduce(0.0) { $0 + ($1.micros[n.rawValue] ?? 0) }
            value = grams / n.unit.gramsPerUnit
        }
        return (value * 100).rounded() / 100
    }

    // Texto legible
    static func summaryText(on day: Date?) throws -> String {
        let start = startOfDay(day)
        let items = try entries(on: start)
        let title = start.formatted(.dateTime.weekday(.wide).day().month(.wide).year()
            .locale(Locale(identifier: "es_ES")))
        guard !items.isEmpty else { return "\(title)\nSin registros." }

        let t = items.reduce(Macros.zero) { $0 + $1.macros }
        var lines = ["\(title)",
                     "Total: \(fmt(t.kcal)) kcal · P \(fmt(t.protein, decimals: 1)) g · C \(fmt(t.carbs, decimals: 1)) g · G \(fmt(t.fat, decimals: 1)) g"]
        for meal in MealType.allCases {
            let group = items.filter { $0.meal == meal }
            guard !group.isEmpty else { continue }
            lines.append("")
            lines.append("\(meal.title) (\(fmt(group.reduce(0) { $0 + $1.kcal })) kcal)")
            for e in group {
                lines.append("- \(e.name) \(fmt(e.grams)) g: \(fmt(e.kcal)) kcal · P \(fmt(e.protein, decimals: 1)) · C \(fmt(e.carbs, decimals: 1)) · G \(fmt(e.fat, decimals: 1))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // CSV (una fila por alimento)
    static func csv(on day: Date?) throws -> (name: String, data: Data) {
        let start = startOfDay(day)
        let items = try entries(on: start)

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.dateFormat = "yyyy-MM-dd"

        func q(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func num(_ v: Double) -> String { String(format: "%.2f", v) }

        var header = ["fecha", "comida", "alimento", "marca", "gramos", "kcal",
                      "proteina_g", "carbohidratos_g", "grasas_g"]
        header += Nutrient.allCases.map {
            "\($0.rawValue)_\($0.unit.symbol.replacingOccurrences(of: "µ", with: "u"))"
        }

        var rows = [header.joined(separator: ",")]
        for e in items {
            let micros = e.micros
            var cols = [dayFmt.string(from: e.date), q(e.meal.title), q(e.name), q(e.brand ?? ""),
                        num(e.grams), num(e.kcal), num(e.protein), num(e.carbs), num(e.fat)]
            for n in Nutrient.allCases {
                let grams = micros[n.rawValue] ?? 0
                cols.append(grams > 0 ? num(grams / n.unit.gramsPerUnit) : "")
            }
            rows.append(cols.joined(separator: ","))
        }
        let name = "macros-\(dayFmt.string(from: start)).csv"
        return (name, Data(rows.joined(separator: "\n").utf8))
    }
}

// MARK: - Acciones para Atajos

struct GetNutrientIntent: AppIntent {
    static let title: LocalizedStringResource = "Obtener nutriente de un día"
    static let description = IntentDescription(
        "Devuelve el total de calorías, macros o micronutrientes de un día (kcal, g, mg o µg según el nutriente). Úsalo con «Registrar muestra de salud» para llevarlo a Apple Salud.",
        categoryName: "Exportar")

    @Parameter(title: "Nutriente", default: .calories)
    var nutrient: NutrientOption

    @Parameter(title: "Día", description: "Si lo dejas vacío, se usa hoy.")
    var day: Date?

    @Parameter(title: "Comida", default: .all)
    var meal: MealFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Obtener \(\.$nutrient) del día \(\.$day)") {
            \.$meal
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        let items = try NutritionExport.entries(on: day, meal: meal)
        return .result(value: NutritionExport.total(nutrient, in: items))
    }
}

struct ExportDayTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Exportar la comida de un día (texto)"
    static let description = IntentDescription(
        "Devuelve un resumen en texto de todo lo que comiste un día, con totales por comida.",
        categoryName: "Exportar")

    @Parameter(title: "Día", description: "Si lo dejas vacío, se usa hoy.")
    var day: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Exportar la comida del día \(\.$day) como texto")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try NutritionExport.summaryText(on: day))
    }
}

struct ExportDayCSVIntent: AppIntent {
    static let title: LocalizedStringResource = "Exportar la comida de un día (CSV)"
    static let description = IntentDescription(
        "Devuelve un archivo CSV con un alimento por fila, con macros y micronutrientes.",
        categoryName: "Exportar")

    @Parameter(title: "Día", description: "Si lo dejas vacío, se usa hoy.")
    var day: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Exportar la comida del día \(\.$day) como CSV")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let file = try NutritionExport.csv(on: day)
        return .result(value: IntentFile(data: file.data, filename: file.name, type: .commaSeparatedText))
    }
}
