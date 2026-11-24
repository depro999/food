import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Hoy", systemImage: "fork.knife") }
            HistoryView()
                .tabItem { Label("Historial", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
    }
}
