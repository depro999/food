import SwiftUI
import SwiftData

/// Pantalla para añadir alimentos. Con `onPick` (modo receta) devuelve ingredientes en lugar
/// de guardarlos en el diario, con las mismas opciones: escáner, foto con IA, código y búsqueda.
struct AddFoodView: View {
    let date: Date
    let meal: MealType
    let onPick: (([RecipeItem]) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var path: [FoodItem] = []
    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var isLoading = false
    @State private var searchError: String?
    @State private var alertMessage: String?
    @State private var showScanner = false
    @State private var showPhoto = false
    @State private var manualCode = ""

    private let service = OpenFoodFactsService()

    init(date: Date, meal: MealType, onPick: (([RecipeItem]) -> Void)? = nil) {
        self.date = date
        self.meal = meal
        self.onPick = onPick
    }

    private var pickSingle: ((RecipeItem) -> Void)? {
        guard let onPick else { return nil }
        return { onPick([$0]) }
    }

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
                    if onPick != nil {
                        NavigationLink {
                            ManualItemForm { item in
                                onPick?([item])
                                dismiss()
                            }
                        } label: {
                            Label("Añadir manualmente", systemImage: "square.and.pencil")
                        }
                    }
                }

                if onPick == nil, !recipes.isEmpty {
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
                    } else if let searchError {
                        Text(searchError).foregroundStyle(.red).font(.callout)
                    } else if results.isEmpty {
                        Text(query.isEmpty ? "Busca un alimento por nombre o marca." : "Sin resultados.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { item in
                        NavigationLink(value: item) { FoodRow(item: item) }
                    }
                }
            }
            .navigationTitle(onPick == nil ? meal.title : "Añadir ingrediente")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Buscar alimento")
            .onSubmit(of: .search) { Task { await search() } }
            // Búsqueda automática mientras escribes (con pausa de 0,5 s)
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                guard q.count >= 3 else {
                    isLoading = false
                    if q.isEmpty { results = []; searchError = nil }
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await search()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .navigationDestination(for: FoodItem.self) { item in
                FoodDetailView(food: item, date: date, initialMeal: meal,
                               onPick: pickSingle, onSaved: { dismiss() })
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
                PhotoAnalysisView(date: date, meal: meal,
                                  onSaved: { showPhoto = false; dismiss() },
                                  onPickItems: onPick)
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
        searchError = nil
        do {
            let found = try await service.search(q)
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            if let off = error as? OpenFoodFactsService.OFFError {
                searchError = off.localizedDescription
            } else {
                searchError = "No se pudo completar la búsqueda. Revisa tu conexión e inténtalo de nuevo."
            }
        }
        isLoading = false
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
