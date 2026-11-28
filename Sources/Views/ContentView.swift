import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("healthSync") private var healthSync = false
    @Query(filter: #Predicate<FoodEntry> { $0.healthSynced == false }) private var unsynced: [FoodEntry]

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Hoy", systemImage: "fork.knife") }
            RecipesView()
                .tabItem { Label("Recetas", systemImage: "book.closed.fill") }
            HistoryView()
                .tabItem { Label("Historial", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
        // Añade las recetas recurrentes de hoy al abrir la app y al volver a ella (p. ej. otro día).
        .task {
            RecipeScheduler.applyDue(context: context)
            syncHealth()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                RecipeScheduler.applyDue(context: context)
                syncHealth()
            }
        }
        // Cualquier registro nuevo (a mano, receta, foto…) se envía a Apple Salud.
        .onChange(of: unsynced.count) { _, _ in syncHealth() }
        .onChange(of: healthSync) { _, _ in syncHealth() }
    }

    private func syncHealth() {
        guard healthSync, !unsynced.isEmpty else { return }
        let pending = Array(unsynced)
        Task { @MainActor in await HealthSync.shared.sync(pending) }
    }
}
