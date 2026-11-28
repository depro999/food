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
    /// IA que ha respondido.
    var provider: AIProvider?
    /// IAs que se han saltado antes (con el motivo).
    var skipped: [String] = []
}

// MARK: - Proveedores

enum AIProvider: String, CaseIterable, Identifiable {
    case claude, openai, gemini, deepseek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude (Anthropic)"
        case .openai: "ChatGPT (OpenAI)"
        case .gemini: "Gemini (Google)"
        case .deepseek: "DeepSeek"
        }
    }

    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .openai: "ChatGPT"
        case .gemini: "Gemini"
        case .deepseek: "DeepSeek"
        }
    }

    var keychainKey: String {
        switch self {
        case .claude: "anthropic_api_key"
        case .openai: "openai_api_key"
        case .gemini: "gemini_api_key"
        case .deepseek: "deepseek_api_key"
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: "claude-sonnet-5-5"
        case .openai: "gpt-4.1-mini"
        case .gemini: "gemini-flash-latest"
        case .deepseek: "deepseek-flash"
        }
    }

    var modelKey: String { self == .claude ? "aiModel" : "aiModel.\(rawValue)" }
    var enabledKey: String { "aiEnabled.\(rawValue)" }

    var keyHint: String {
        switch self {
        case .claude: "sk-ant-…"
        case .openai: "sk-…"
        case .gemini: "AIza…"
        case .deepseek: "sk-…"
        }
    }

    var consoleURL: URL {
        switch self {
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        case .deepseek: URL(string: "https://platform.deepseek.com/api_keys")!
        }
    }

    var apiKey: String? {
        guard let k = Keychain.get(keychainKey), !k.isEmpty else { return nil }
        return k
    }

    var model: String {
        let m = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return m.trimmingCharacters(in: .whitespaces).isEmpty ? defaultModel : m
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    // Orden de prioridad (se guarda como "openai,gemini,claude,deepseek")
    static let defaultOrder: [AIProvider] = [.openai, .gemini, .claude, .deepseek]

    static func savedOrder() -> [AIProvider] {
        let raw = UserDefaults.standard.string(forKey: "aiProviderOrder") ?? ""
        var list: [AIProvider] = []
        for part in raw.split(separator: ",") {
            if let p = AIProvider(rawValue: String(part)), !list.contains(p) { list.append(p) }
        }
        for p in defaultOrder where !list.contains(p) { list.append(p) }
        return list
    }

    static func saveOrder(_ list: [AIProvider]) {
        UserDefaults.standard.set(list.map(\.rawValue).joined(separator: ","), forKey: "aiProviderOrder")
    }

    /// Proveedores activados y con clave, en orden de prioridad.
    static func active() -> [AIProvider] {
        savedOrder().filter { $0.isEnabled && $0.apiKey != nil }
    }
}

/// Recuerda un rato qué proveedores se han quedado sin cuota/saldo para no volver a intentarlo
/// en cada foto (se prueban los últimos si los demás fallan).
actor AICooldown {
    static let shared = AICooldown()
    private var until: [AIProvider: Date] = [:]

    func mark(_ p: AIProvider, seconds: TimeInterval) {
        until[p] = Date().addingTimeInterval(seconds)
    }

    func ordered(_ list: [AIProvider]) -> [AIProvider] {
        let now = Date()
        let ready = list.filter { (until[$0] ?? .distantPast) <= now }
        let cooling = list.filter { (until[$0] ?? .distantPast) > now }
        return ready + cooling
    }
}

// MARK: - Errores

enum AIError: LocalizedError {
    case missingKey, badImage, server(Int, String), parse, allFailed([String])

    var statusCode: Int? {
        if case .server(let code, _) = self { return code }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .missingKey: "Añade al menos una API key (ChatGPT, Gemini, Claude o DeepSeek) en Ajustes para usar el análisis con IA."
        case .badImage: "No se pudo procesar la imagen."
        case .server(let code, let msg): "Error del servidor (\(code)). \(msg.prefix(200))"
        case .parse: "No pude interpretar la respuesta de la IA. Inténtalo de nuevo."
        case .allFailed(let list): "Ninguna IA pudo analizar la foto:\n" + list.joined(separator: "\n")
        }
    }

    /// Motivo breve para mostrar al usuario.
    var shortReason: String {
        switch self {
        case .server(let code, _):
            switch code {
            case 401, 403: return "clave no válida o sin acceso"
            case 402: return "sin saldo"
            case 404: return "modelo no encontrado"
            case 400: return "petición rechazada (revisa el modelo)"
            case 429: return "límite o cuota agotada"
            case 500...599: return "servicio saturado"
            default: return "error \(code)"
            }
        case .parse: return "respuesta no válida"
        default: return errorDescription ?? "error"
        }
    }
}

// MARK: - Reconocedor

struct AIFoodRecognizer {
    static let keychainKey = AIProvider.claude.keychainKey
    static let defaultModel = AIProvider.claude.defaultModel

    private struct ClaudeResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct GeminiResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
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

    /// Prueba las IAs en orden de prioridad; si una falla (sin saldo, límite, clave mala, caída…)
    /// pasa automáticamente a la siguiente.
    func analyze(image: UIImage, hint: String = "") async throws -> AIAnalysis {
        let candidates = AIProvider.active()
        guard !candidates.isEmpty else { throw AIError.missingKey }
        guard let jpeg = image.resizedJPEG() else { throw AIError.badImage }

        var userText = "Analiza esta comida y estima los macros."
        if !hint.trimmingCharacters(in: .whitespaces).isEmpty {
            userText += " Contexto del usuario: \(hint)"
        }

        var failures: [String] = []
        var skipped: [String] = []
        for provider in await AICooldown.shared.ordered(candidates) {
            do {
                let text = try await send(provider, jpeg: jpeg, userText: userText)
                var result = try parse(text)
                result.provider = provider
                result.skipped = skipped
                return result
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw error }
                let reason: String
                if let ai = error as? AIError {
                    reason = ai.shortReason
                    if let code = ai.statusCode {
                        // Sin saldo / límite / clave mala: no insistir durante un rato
                        if code == 402 || code == 429 { await AICooldown.shared.mark(provider, seconds: 15 * 60) }
                        if code == 401 || code == 403 { await AICooldown.shared.mark(provider, seconds: 30 * 60) }
                    }
                } else {
                    reason = "sin conexión o tiempo agotado"
                }
                failures.append("• \(provider.shortName): \(reason)")
                skipped.append("\(provider.shortName) (\(reason))")
            }
        }
        throw AIError.allFailed(failures)
    }

    // MARK: Envío por proveedor

    private func send(_ p: AIProvider, jpeg: Data, userText: String) async throws -> String {
        guard let key = p.apiKey else { throw AIError.missingKey }
        let model = p.model
        let b64 = jpeg.base64EncodedString()

        var req: URLRequest
        let body: [String: Any]

        switch p {
        case .claude:
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": model,
                "max_tokens": 4096,
                "system": system,
                "messages": [[
                    "role": "user",
                    "content": [
                        ["type": "image",
                         "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]],
                        ["type": "text", "text": userText]
                    ]
                ]]
            ]

        case .openai, .deepseek:
            let url = p == .openai ? "https://api.openai.com/v1/chat/completions"
                                   : "https://api.deepseek.com/chat/completions"
            req = URLRequest(url: URL(string: url)!)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            var b: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": [
                        ["type": "text", "text": userText],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]]
                    ]]
                ]
            ]
            if p == .openai { b["max_completion_tokens"] = 4096 } else { b["max_tokens"] = 8192 }
            body = b

        case .gemini:
            let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            req = URLRequest(url: URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models/\(encoded):generateContent")!)
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            body = [
                "system_instruction": ["parts": [["text": system]]],
                "contents": [[
                    "role": "user",
                    "parts": [
                        ["inline_data": ["mime_type": "image/jpeg", "data": b64]],
                        ["text": userText]
                    ]
                ]],
                "generationConfig": ["maxOutputTokens": 8192, "temperature": 0.2]
            ]
        }

        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.parse }
        guard http.statusCode == 200 else {
            throw AIError.server(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let decoder = JSONDecoder()
        switch p {
        case .claude:
            let r = try decoder.decode(ClaudeResponse.self, from: data)
            return r.content.compactMap(\.text).joined()
        case .openai, .deepseek:
            let r = try decoder.decode(ChatResponse.self, from: data)
            return r.choices.first?.message.content ?? ""
        case .gemini:
            let r = try decoder.decode(GeminiResponse.self, from: data)
            return (r.candidates?.first?.content?.parts ?? []).compactMap(\.text).joined()
        }
    }

    // MARK: Interpretación de la respuesta (común a todas las IAs)

    private func parse(_ text: String) throws -> AIAnalysis {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end,
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
