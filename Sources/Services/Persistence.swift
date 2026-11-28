import SwiftData

/// Contenedor único de SwiftData, compartido por la app y por los Atajos (App Intents),
/// para que ambos lean y escriban la misma base de datos.
enum Persistence {
    static let container: ModelContainer = {
        do { return try ModelContainer(for: FoodEntry.self, Recipe.self) }
        catch { fatalError("No se pudo abrir la base de datos: \(error)") }
    }()
}
