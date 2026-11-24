import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

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
        .task { RecipeScheduler.applyDue(context: context) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { RecipeScheduler.applyDue(context: context) }
        }
    }
}
