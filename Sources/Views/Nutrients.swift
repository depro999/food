import Foundation
import HealthKit

/// Micronutrientes de un alimento: clave = `Nutrient.rawValue`, valor = GRAMOS.
typealias Micros = [String: Double]

enum NutrientUnit {
    case g, mg, ug

    var symbol: String {
        switch self {
        case .g: return "g"
        case .mg: return "mg"
        case .ug: return "µg"
        }
    }

    var gramsPerUnit: Double {
        switch self {
        case .g: return 1
        case .mg: return 1e-3
        case .ug: return 1e-6
        }
    }
}

enum Nutrient: String, CaseIterable, Identifiable {
    case fiber, sugars, saturatedFat, monounsaturatedFat, polyunsaturatedFat
    case cholesterol, sodium, potassium, calcium, iron, magnesium, zinc, phosphorus
    case copper, manganese, selenium, iodine, chromium, molybdenum, chloride
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminK
    case thiamin, riboflavin, niacin, vitaminB6, folate, vitaminB12, biotin, pantothenicAcid
    case caffeine

    var id: String { rawValue }

    /// (título, unidad de visualización, clave de Open Food Facts sin "_100g", tipo de HealthKit)
    private var info: (title: String, unit: NutrientUnit, off: String, hk: HKQuantityTypeIdentifier) {
        switch self {
        case .fiber: return ("Fibra", .g, "fiber", .dietaryFiber)
        case .sugars: return ("Azúcares", .g, "sugars", .dietarySugar)
        case .saturatedFat: return ("Grasa saturada", .g, "saturated-fat", .dietaryFatSaturated)
        case .monounsaturatedFat: return ("Grasa monoinsaturada", .g, "monounsaturated-fat", .dietaryFatMonounsaturated)
        case .polyunsaturatedFat: return ("Grasa poliinsaturada", .g, "polyunsaturated-fat", .dietaryFatPolyunsaturated)
        case .cholesterol: return ("Colesterol", .mg, "cholesterol", .dietaryCholesterol)
        case .sodium: return ("Sodio", .mg, "sodium", .dietarySodium)
        case .potassium: return ("Potasio", .mg, "potassium", .dietaryPotassium)
        case .calcium: return ("Calcio", .mg, "calcium", .dietaryCalcium)
        case .iron: return ("Hierro", .mg, "iron", .dietaryIron)
        case .magnesium: return ("Magnesio", .mg, "magnesium", .dietaryMagnesium)
        case .zinc: return ("Zinc", .mg, "zinc", .dietaryZinc)
        case .phosphorus: return ("Fósforo", .mg, "phosphorus", .dietaryPhosphorus)
        case .copper: return ("Cobre", .mg, "copper", .dietaryCopper)
        case .manganese: return ("Manganeso", .mg, "manganese", .dietaryManganese)
        case .selenium: return ("Selenio", .ug, "selenium", .dietarySelenium)
        case .iodine: return ("Yodo", .ug, "iodine", .dietaryIodine)
        case .chromium: return ("Cromo", .ug, "chromium", .dietaryChromium)
        case .molybdenum: return ("Molibdeno", .ug, "molybdenum", .dietaryMolybdenum)
        case .chloride: return ("Cloruro", .mg, "chloride", .dietaryChloride)
        case .vitaminA: return ("Vitamina A", .ug, "vitamin-a", .dietaryVitaminA)
        case .vitaminC: return ("Vitamina C", .mg, "vitamin-c", .dietaryVitaminC)
        case .vitaminD: return ("Vitamina D", .ug, "vitamin-d", .dietaryVitaminD)
        case .vitaminE: return ("Vitamina E", .mg, "vitamin-e", .dietaryVitaminE)
        case .vitaminK: return ("Vitamina K", .ug, "vitamin-k", .dietaryVitaminK)
        case .thiamin: return ("B1 (tiamina)", .mg, "vitamin-b1", .dietaryThiamin)
        case .riboflavin: return ("B2 (riboflavina)", .mg, "vitamin-b2", .dietaryRiboflavin)
        case .niacin: return ("B3 (niacina)", .mg, "vitamin-pp", .dietaryNiacin)
        case .vitaminB6: return ("Vitamina B6", .mg, "vitamin-b6", .dietaryVitaminB6)
        case .folate: return ("B9 (folato)", .ug, "vitamin-b9", .dietaryFolate)
        case .vitaminB12: return ("Vitamina B12", .ug, "vitamin-b12", .dietaryVitaminB12)
        case .biotin: return ("Biotina", .ug, "biotin", .dietaryBiotin)
        case .pantothenicAcid: return ("B5 (ác. pantoténico)", .mg, "pantothenic-acid", .dietaryPantothenicAcid)
        case .caffeine: return ("Cafeína", .mg, "caffeine", .dietaryCaffeine)
        }
    }

    var title: String { info.title }
    var unit: NutrientUnit { info.unit }
    var offKey: String { info.off + "_100g" }
    var healthIdentifier: HKQuantityTypeIdentifier { info.hk }

    /// Formatea un valor en gramos en la unidad natural del nutriente.
    func format(_ grams: Double) -> String {
        let v = grams / unit.gramsPerUnit
        let decimals = v >= 100 ? 0 : (v >= 10 ? 1 : 2)
        return "\(fmt(v, decimals: decimals)) \(unit.symbol)"
    }
}
