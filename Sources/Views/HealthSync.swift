#if HEALTHKIT
import Foundation
import HealthKit

/// Guarda los registros del diario en Apple Salud (energía, macros y micronutrientes).
/// Cada muestra lleva el id del registro en sus metadatos, así se puede borrar después
/// y, gracias al identificador de sincronización, nunca se duplica.
@MainActor
final class HealthSync {
    static let shared = HealthSync()
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()
    private let entryKey = "MacroTrackerEntryID"
    private var inFlight = Set<UUID>()

    private var allTypes: [HKQuantityType] {
        [HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
         HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal)]
        + Nutrient.allCases.map { HKQuantityType($0.healthIdentifier) }
    }

    /// Pide permiso de escritura. Devuelve un mensaje de error o nil si todo va bien.
    func requestAuthorization() async -> String? {
        guard Self.isAvailable else { return "Apple Salud no está disponible en este dispositivo." }
        do {
            let share: Set<HKSampleType> = Set(allTypes.map { $0 as HKSampleType })
            try await store.requestAuthorization(toShare: share, read: [])
        } catch {
            return error.localizedDescription
        }
        if store.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingDenied {
            return "Permiso denegado. Actívalo en Ajustes › Salud › Datos y acceso › Macros."
        }
        return nil
    }

    /// Envía a Salud los registros pendientes.
    func sync(_ entries: [FoodEntry]) async {
        guard Self.isAvailable else { return }
        for e in entries where !inFlight.contains(e.id) {
            inFlight.insert(e.id)
            defer { inFlight.remove(e.id) }
            let samples = makeSamples(for: e)
            if samples.isEmpty { e.healthSynced = true; continue }
            do {
                try await store.save(samples)
                e.healthSynced = true
            } catch {
                // Se reintentará la próxima vez que se abra la app.
            }
        }
    }

    /// Borra de Salud las muestras de un registro (si se habían enviado).
    func delete(_ entry: FoodEntry) {
        guard entry.healthSynced, Self.isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: entryKey,
                                                    allowedValues: [entry.id.uuidString])
        let types = allTypes
        Task {
            for t in types { _ = try? await store.deleteObjects(of: t, predicate: predicate) }
        }
    }

    private func makeSamples(for e: FoodEntry) -> [HKQuantitySample] {
        let date = min(e.date, Date())
        var samples: [HKQuantitySample] = []

        func add(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double) {
            guard value > 0, value.isFinite else { return }
            let meta: [String: Any] = [
                HKMetadataKeyFoodType: e.name,
                entryKey: e.id.uuidString,
                HKMetadataKeySyncIdentifier: "\(e.id.uuidString).\(id.rawValue)",
                HKMetadataKeySyncVersion: 1
            ]
            samples.append(HKQuantitySample(type: HKQuantityType(id),
                                            quantity: HKQuantity(unit: unit, doubleValue: value),
                                            start: date, end: date, metadata: meta))
        }

        add(.dietaryEnergyConsumed, .kilocalorie(), e.kcal)
        add(.dietaryProtein, .gram(), e.protein)
        add(.dietaryCarbohydrates, .gram(), e.carbs)
        add(.dietaryFatTotal, .gram(), e.fat)
        let micros = e.micros
        for n in Nutrient.allCases {
            if let v = micros[n.rawValue] { add(n.healthIdentifier, .gram(), v) }
        }
        return samples
    }
}

#else
import Foundation

/// Versión sin HealthKit (compilaciones sin cuenta de Apple Developer de pago).
/// Para activar Apple Salud, añade HEALTHKIT a "Active Compilation Conditions" y firma con HealthKit.
@MainActor
final class HealthSync {
    static let shared = HealthSync()
    static var isAvailable: Bool { false }

    func requestAuthorization() async -> String? {
        "Apple Salud no está disponible en esta compilación."
    }
    func sync(_ entries: [FoodEntry]) async {}
    func delete(_ entry: FoodEntry) {}
}
#endif
