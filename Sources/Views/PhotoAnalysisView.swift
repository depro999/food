import SwiftUI
import PhotosUI
import SwiftData

struct PhotoAnalysisView: View {
    let date: Date
    let meal: MealType
    let onSaved: () -> Void
    /// Si no es nil, los alimentos se devuelven a una receta en vez de guardarse en el diario.
    let onPickItems: (([RecipeItem]) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var hint = ""
    @State private var foods: [DetectedFood] = []
    @State private var notes: String?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var selectedMeal: MealType

    init(date: Date, meal: MealType, onSaved: @escaping () -> Void,
         onPickItems: (([RecipeItem]) -> Void)? = nil) {
        self.date = date
        self.meal = meal
        self.onSaved = onSaved
        self.onPickItems = onPickItems
        _selectedMeal = State(initialValue: meal)
    }

    private var total: Macros {
        foods.filter(\.isSelected).reduce(.zero) { $0 + $1.macros }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                    }
                    HStack {
                        Button { showCamera = true } label: {
                            Label("Cámara", systemImage: "camera.fill")
                        }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        Spacer()
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Galería", systemImage: "photo.on.rectangle")
                        }
                    }
                    .buttonStyle(.borderless)
                }

                if image != nil {
                    Section("Contexto (opcional)") {
                        TextField("Ej: pollo a la plancha con 150 g de arroz", text: $hint, axis: .vertical)
                    }
                    Section {
                        Button {
                            Task { await analyze() }
                        } label: {
                            HStack {
                                Spacer()
                                if isAnalyzing { ProgressView().padding(.trailing, 6) }
                                Text(isAnalyzing ? "Analizando…" : "Analizar con IA").bold()
                                Spacer()
                            }
                        }
                        .disabled(isAnalyzing)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.callout) }
                }

                if !foods.isEmpty {
                    Section("Alimentos detectados") {
                        ForEach($foods) { $f in
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: $f.isSelected) {
                                    Text(f.name).font(.headline)
                                }
                                Stepper(value: $f.grams, in: 5...2000, step: 10) {
                                    Text("\(fmt(f.grams)) g")
                                }
                                Text("\(fmt(f.macros.kcal)) kcal · P \(fmt(f.macros.protein, decimals: 1)) · C \(fmt(f.macros.carbs, decimals: 1)) · G \(fmt(f.macros.fat, decimals: 1))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Section("Total seleccionado") {
                        Text("\(fmt(total.kcal)) kcal · P \(fmt(total.protein, decimals: 1)) g · C \(fmt(total.carbs, decimals: 1)) g · G \(fmt(total.fat, decimals: 1)) g")
                            .font(.subheadline.weight(.semibold))
                        if let notes, !notes.isEmpty {
                            Text(notes).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("Son estimaciones: ajusta los gramos si conoces el peso real.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Section {
                        if onPickItems == nil {
                            Picker("Comida", selection: $selectedMeal) {
                                ForEach(MealType.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        Button {
                            save()
                        } label: {
                            Text(onPickItems == nil ? "Añadir al diario" : "Añadir a la receta")
                                .frame(maxWidth: .infinity).bold()
                        }
                        .disabled(total.kcal <= 0)
                    }
                }
            }
            .navigationTitle("Foto con IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { picked in
                    image = picked
                    foods = []; notes = nil; errorMessage = nil
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        image = ui
                        foods = []; notes = nil; errorMessage = nil
                    }
                }
            }
        }
    }

    private func analyze() async {
        guard let image else { return }
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        do {
            let result = try await AIFoodRecognizer().analyze(image: image, hint: hint)
            foods = result.foods
            notes = result.notes
            if foods.isEmpty { errorMessage = result.notes ?? "No se detectó comida en la imagen." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let selected = foods.filter(\.isSelected)
        if let onPickItems {
            onPickItems(selected.map {
                RecipeItem(name: $0.name, brand: nil, grams: $0.grams, macros: $0.macros, micros: $0.micros)
            })
        } else {
            for f in selected {
                context.insert(FoodEntry(date: entryTimestamp(for: date), meal: selectedMeal,
                                         name: f.name, brand: nil, grams: f.grams,
                                         macros: f.macros, source: "ai", micros: f.micros))
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSaved()
    }
}
