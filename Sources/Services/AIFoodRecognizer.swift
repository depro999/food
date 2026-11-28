import UIKit

/// Alimento detectado por la IA en una foto. Los valores "base" son los de la porción estimada;
/// al cambiar `grams` los macros se escalan proporcionalmente.
struct DetectedFood: Identifiable {
    let id = UUID()
    var name: String
    var baseGrams: Double
    var baseMacros: Macros
    var grams: Double
    var isSelected = true
    var baseMicros: Micros = [:]   // gramos, para baseGrams

    var macros: Macros {
        let f = baseGrams > 0 ? grams / baseGrams : 0
        return Macros(kcal: baseMacros.kcal * f, protein: baseMacros.protein * f,
                      carbs: baseMacros.carbs * f, fat: baseMacros.fat * f)
    }

    var micros: Micros {
        let f = baseGrams > 0 ? grams / baseGrams : 0
        return baseMicros.mapValues { $0 * f }
    }
}

struct AIAnalysis {
    var foods: [DetectedFood]
    var notes: String?
}

enum AIError: LocalizedError {
    case missingKey, badImage, server(Int, String), parse

    var errorDescription: String? {
        switch self {
        case .missingKey: "Añade tu API key de Anthropic en Ajustes para usar el análisis con IA."
        case .badImage: "No se pudo procesar la imagen."
        case .server(let code, let msg): "Error del servidor (\(code)). \(msg.prefix(200))"
        case .parse: "No pude interpretar la respuesta de la IA. Inténtalo de nuevo."
        }
    }
}

struct AIFoodRecognizer {
    static let keychainKey = "anthropic_api_key"
    static let defaultModel = "claude-sonnet-5-5"

    private struct APIMessage: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    private struct DTO: Decodable {
        struct Item: Decodable {
            let name: String
            let grams: Double
            let kcal: Double
            let protein_g: Double
            let carbs_g: Double
            let fat_g: Double
            let micros: [String: FlexDouble]?
        }
        let foods: [Item]
        let notes: String?
    }

    private var system: String {
        let keys = Nutrient.allCases.map { "\($0.rawValue) (\($0.unit.symbol))" }.joined(separator: ", ")
        return """
        Eres un nutricionista experto en estimar el contenido nutricional de platos a partir de fotos. \
        Identifica cada alimento visible, estima su peso en gramos (cocinado/tal como se ve) y sus macros \
        TOTALES para esa porción. Usa un plato o cubiertos como referencia de tamaño. \
        Responde ÚNICAMENTE con JSON válido, sin texto adicional ni markdown, con este formato exacto: \
        {"foods":[{"name":"string en español","grams":number,"kcal":number,"protein_g":number,"carbs_g":number,"fat_g":number,"micros":{"clave":number}}],"notes":"string opcional con aclaraciones o nivel de incertidumbre"}. \
        En "micros" estima los micronutrientes TOTALES de esa porción usando SOLO estas claves y estas unidades: \(keys). \
        Incluye únicamente los que tengan un valor apreciable y omite el resto. \
        Si no hay comida en la imagen devuelve {"foods":[],"notes":"No veo comida en la imagen"}.
        """
    }

    func analyze(image: UIImage, hint: String = "") async throws -> AIAnalysis {
        guard let key = Keychain.get(Self.keychainKey), !key.isEmpty else { throw AIError.missingKey }
        guard let jpeg = image.resizedJPEG() else { throw AIError.badImage }
        let model = UserDefaults.standard.string(forKey: "aiModel").flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.defaultModel

        var userText = "Analiza esta comida y estima los macros."
        if !hint.trimmingCharacters(in: .whitespaces).isEmpty {
            userText += " Contexto del usuario: \(hint)"
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64", "media_type": "image/jpeg",
                                "data": jpeg.base64EncodedString()]],
                    ["type": "text", "text": userText]
                ]
            ]]
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.parse }
        guard http.statusCode == 200 else {
            throw AIError.server(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let msg = try JSONDecoder().decode(APIMessage.self, from: data)
        let text = msg.content.compactMap(\.text).joined()
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let dto = try? JSONDecoder().decode(DTO.self, from: Data(text[start...end].utf8))
        else { throw AIError.parse }

        let foods = dto.foods.map { item -> DetectedFood in
            var micros: Micros = [:]
            for (k, v) in item.micros ?? [:] {
                if let n = Nutrient(rawValue: k), let x = v.value, x > 0 {
                    micros[k] = x * n.unit.gramsPerUnit
                }
            }
            return DetectedFood(name: item.name, baseGrams: max(item.grams, 1),
                                baseMacros: Macros(kcal: item.kcal, protein: item.protein_g,
                                                   carbs: item.carbs_g, fat: item.fat_g),
                                grams: max(item.grams, 1), baseMicros: micros)
        }
        return AIAnalysis(foods: foods, notes: dto.notes)
    }
}

extension UIImage {
    /// Reduce el tamaño para ahorrar datos y coste de la API.
    func resizedJPEG(maxSide: CGFloat = 1280, quality: CGFloat = 0.7) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return img.jpegData(compressionQuality: quality)
    }
}
