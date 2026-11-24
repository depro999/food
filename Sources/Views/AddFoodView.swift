import SwiftUI
import SwiftData

struct AddFoodView: View {
    let date: Date
    let meal: MealType

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var path: [FoodItem] = []
    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var isLoading = false
    @State private var alertMessage: String?
    @State private var showScanner = false
    @State private var showPhoto = false
    @State private var manualCode = ""

    private let service = OpenFoodFactsService()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button { showScanner = true } label: {
                        Label("Escanear código de barras / QR", systemImage: "barcode.viewfinder")
                    }
                    Button { showPhoto = true } label: {
                        Label("Foto del plato con IA", systemImage: "camera.viewfinder")
                    }
                    HStack {
                        TextField("Código manual (EAN)", text: $manualCode)
                            .keyboardType(.numberPad)
                        Button("Buscar") { Task { await lookup(manualCode) } }
                            .disabled(manualCode.count < 8)
                    }
                }

                if !recipes.isEmpty {
                    Section("Mis recetas") {
                        ForEach(recipes.filter { !$0.items.isEmpty }) { r in
                            Button {
                                RecipeScheduler.add(r, to: date, meal: meal, context: context)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name)
                                        Text(Weekday.summary(r.weekdays))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(fmt(r.total.kcal)) kcal")
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section("Resultados") {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if results.isEmpty {
                        Text(query.isEmpty ? "Busca un alimento por nombre o marca." : "Sin resultados.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { item in
                        NavigationLink(value: item) { FoodRow(item: item) }
                    }
                }
            }
            .navigationTitle(meal.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Buscar alimento")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .navigationDestination(for: FoodItem.self) { item in
                FoodDetailView(food: item, date: date, initialMeal: meal) { dismiss() }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScannerScreen { payload in
                    showScanner = false
                    guard let code = extractProductCode(from: payload) else {
                        alertMessage = "Ese código no contiene un producto reconocible:\n\(payload.prefix(120))"
                        return
                    }
                    Task { await lookup(code) }
                }
            }
            .sheet(isPresented: $showPhoto) {
                PhotoAnalysisView(date: date, meal: meal) {
                    showPhoto = false
                    dismiss()
                }
            }
            .alert("Aviso", isPresented: Binding(get: { alertMessage != nil },
                                                 set: { if !$0 { alertMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(alertMessage ?? "") }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        isLoading = true
        defer { isLoading = false }
        do { results = try await service.search(q) }
        catch { alertMessage = "No se pudo conectar con la base de datos. Revisa tu conexión." }
    }

    private func lookup(_ code: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let item = try await service.product(barcode: code)
            path.append(item)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct FoodRow: View {
    let item: FoodItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.imageURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(2)
                if let b = item.brand, !b.isEmpty {
                    Text(b).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(fmt(item.kcalPer100)) kcal · P \(fmt(item.proteinPer100)) · C \(fmt(item.carbsPer100)) · G \(fmt(item.fatPer100)) /100g")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
