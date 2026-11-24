import Foundation

/// Cliente de Open Food Facts (base de datos abierta, gratuita y sin API key).
struct OpenFoodFactsService {
    enum OFFError: LocalizedError {
        case notFound
        var errorDescription: String? {
            "No hemos encontrado ese producto en Open Food Facts. Prueba a buscarlo por nombre o hazle una foto."
        }
    }

    private let fields = "code,product_name,brands,nutriments,serving_quantity,image_front_small_url"

    // Producto por código de barras
    func product(barcode: String) async throws -> FoodItem {
        if let item = try await fetchProduct(barcode) { return item }
        // UPC-A leído como EAN-13 con un 0 delante
        if barcode.count == 13, barcode.hasPrefix("0"),
           let item = try await fetchProduct(String(barcode.dropFirst())) { return item }
        throw OFFError.notFound
    }

    private func fetchProduct(_ code: String) async throws -> FoodItem? {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        comps.queryItems = [URLQueryItem(name: "fields", value: fields)]
        let data = try await fetch(comps.url!)
        guard let r = try? JSONDecoder().decode(OFFResponse.self, from: data),
              r.status == 1 else { return nil }
        return r.product?.toFoodItem(fallbackCode: code)
    }

    // Búsqueda por texto
    func search(_ text: String) async throws -> [FoodItem] {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            URLQueryItem(name: "search_terms", value: text),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "30"),
            URLQueryItem(name: "lc", value: "es"),
            URLQueryItem(name: "fields", value: fields)
        ]
        let data = try await fetch(comps.url!)
        let r = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        return r.products.compactMap { $0.toFoodItem(fallbackCode: nil) }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        // Open Food Facts pide identificar la app
        req.setValue("MacroTracker-iOS/1.0 (contacto@tudominio.com)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}

// MARK: - DTOs

struct FlexDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}

struct OFFResponse: Decodable {
    let status: Int?
    let product: OFFProduct?
}

struct OFFSearchResponse: Decodable {
    let products: [OFFProduct]
}

struct OFFNutriments: Decodable {
    let kcal: FlexDouble?
    let kj: FlexDouble?
    let protein: FlexDouble?
    let carbs: FlexDouble?
    let fat: FlexDouble?

    enum CodingKeys: String, CodingKey {
        case kcal = "energy-kcal_100g"
        case kj = "energy_100g"
        case protein = "proteins_100g"
        case carbs = "carbohydrates_100g"
        case fat = "fat_100g"
    }
}

struct OFFProduct: Decodable {
    let code: String?
    let product_name: String?
    let brands: String?
    let serving_quantity: FlexDouble?
    let image_front_small_url: String?
    let nutriments: OFFNutriments?

    func toFoodItem(fallbackCode: String?) -> FoodItem? {
        guard let name = product_name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, let n = nutriments else { return nil }

        var kcal: Double? = n.kcal?.value
        if kcal == nil, let kj = n.kj?.value { kcal = kj / 4.184 }
        guard let kcalValue = kcal else { return nil }

        return FoodItem(
            name: name,
            brand: brands?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces),
            kcalPer100: kcalValue,
            proteinPer100: n.protein?.value ?? 0,
            carbsPer100: n.carbs?.value ?? 0,
            fatPer100: n.fat?.value ?? 0,
            servingGrams: serving_quantity?.value,
            barcode: code ?? fallbackCode,
            imageURL: image_front_small_url.flatMap(URL.init(string:))
        )
    }
}
