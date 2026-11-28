import Foundation

/// Cliente de Open Food Facts (base de datos abierta, gratuita y sin API key).
struct OpenFoodFactsService {
    enum OFFError: LocalizedError {
        case notFound
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "No hemos encontrado ese producto en Open Food Facts. Prueba a buscarlo por nombre o hazle una foto."
            case .server(let code):
                return "Open Food Facts no responde ahora mismo (error \(code)). Inténtalo de nuevo en unos segundos."
            }
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
        let (data, status) = try await fetch(comps.url!)
        if status == 404 { return nil }   // OFF responde 404 cuando el código no existe
        guard (200..<300).contains(status) else { throw OFFError.server(status) }
        guard let r = try? JSONDecoder().decode(OFFResponse.self, from: data),
              r.status == 1 else { return nil }
        return r.product?.toFoodItem(fallbackCode: code)
    }

    // Búsqueda por texto (con un reintento: el servidor de búsqueda de OFF falla de vez en cuando)
    func search(_ text: String) async throws -> [FoodItem] {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            URLQueryItem(name: "search_terms", value: text),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "30"),
            URLQueryItem(name: "sort_by", value: "unique_scans_n"),
            URLQueryItem(name: "lc", value: "es"),
            URLQueryItem(name: "fields", value: fields)
        ]
        var lastError: Error = OFFError.server(0)
        for attempt in 0..<2 {
            do {
                let (data, status) = try await fetch(comps.url!)
                guard (200..<300).contains(status) else { throw OFFError.server(status) }
                let r = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
                return r.products.compactMap { $0.value?.toFoodItem(fallbackCode: nil) }
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw error }
                lastError = error
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(600)) }
            }
        }
        throw lastError
    }

    private func fetch(_ url: URL) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        // Open Food Facts pide identificar la app
        req.setValue("MacroTracker-iOS/1.0 (contacto@tudominio.com)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 200)
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

/// Decodifica un elemento sin romper toda la lista si ese elemento viene mal formado.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

struct OFFResponse: Decodable {
    let status: Int?
    let product: OFFProduct?
}

struct OFFSearchResponse: Decodable {
    let products: [Lossy<OFFProduct>]
}

/// Todos los campos `*_100g` (en gramos) del producto.
struct OFFNutriments: Decodable {
    let values: [String: Double]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        var out: [String: Double] = [:]
        for key in c.allKeys where key.stringValue.hasSuffix("_100g") {
            if let v = try? c.decode(FlexDouble.self, forKey: key), let d = v.value {
                out[key.stringValue] = d
            }
        }
        values = out
    }

    var kcal: Double? { values["energy-kcal_100g"] }
    var kj: Double? { values["energy_100g"] }
    var protein: Double? { values["proteins_100g"] }
    var carbs: Double? { values["carbohydrates_100g"] }
    var fat: Double? { values["fat_100g"] }
}

struct OFFProduct: Decodable {
    let code: String?
    let product_name: String?
    let brands: String?
    let serving_quantity: FlexDouble?
    let image_front_small_url: String?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case code, product_name, brands, serving_quantity, image_front_small_url, nutriments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try? c.decodeIfPresent(String.self, forKey: .code)
        product_name = try? c.decodeIfPresent(String.self, forKey: .product_name)
        brands = try? c.decodeIfPresent(String.self, forKey: .brands)
        serving_quantity = try? c.decodeIfPresent(FlexDouble.self, forKey: .serving_quantity)
        image_front_small_url = try? c.decodeIfPresent(String.self, forKey: .image_front_small_url)
        // OFF a veces devuelve `[]` en lugar de un objeto cuando no hay datos
        nutriments = try? c.decodeIfPresent(OFFNutriments.self, forKey: .nutriments)
    }

    func toFoodItem(fallbackCode: String?) -> FoodItem? {
        guard let name = product_name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, let n = nutriments else { return nil }

        var kcal: Double? = n.kcal
        if kcal == nil, let kj = n.kj { kcal = kj / 4.184 }
        guard let kcalValue = kcal else { return nil }

        var micros: Micros = [:]
        for nutrient in Nutrient.allCases {
            var v = n.values[nutrient.offKey]
            if nutrient == .sodium, v == nil, let salt = n.values["salt_100g"] { v = salt / 2.5 }
            if let v, v > 0, v < 100 { micros[nutrient.rawValue] = v }
        }

        return FoodItem(
            name: name,
            brand: brands?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces),
            kcalPer100: kcalValue,
            proteinPer100: n.protein ?? 0,
            carbsPer100: n.carbs ?? 0,
            fatPer100: n.fat ?? 0,
            servingGrams: serving_quantity?.value,
            barcode: code ?? fallbackCode,
            imageURL: image_front_small_url.flatMap(URL.init(string:)),
            microsPer100: micros
        )
    }
}
