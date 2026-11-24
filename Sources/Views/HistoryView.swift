import SwiftUI
import SwiftData
import Charts

struct DayTotal: Identifiable {
    var id: Date { date }
    let date: Date
    let macros: Macros
}

struct HistoryView: View {
    @AppStorage("goalKcal") private var goalKcal = 2200.0
    @Query private var entries: [FoodEntry]
    private let days = 7

    init() {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) ?? Date()
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= start }, sort: \.date)
    }

    private var totals: [DayTotal] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let m = entries.filter { cal.isDate($0.date, inSameDayAs: day) }
                .reduce(Macros.zero) { $0 + $1.macros }
            return DayTotal(date: day, macros: m)
        }
    }

    private var average: Macros {
        let logged = totals.filter { $0.macros.kcal > 0 }
        guard !logged.isEmpty else { return .zero }
        let sum = logged.reduce(Macros.zero) { $0 + $1.macros }
        let n = Double(logged.count)
        return Macros(kcal: sum.kcal / n, protein: sum.protein / n, carbs: sum.carbs / n, fat: sum.fat / n)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Calorías · últimos 7 días") {
                    Chart {
                        ForEach(totals) { d in
                            BarMark(x: .value("Día", d.date, unit: .day),
                                    y: .value("kcal", d.macros.kcal))
                            .foregroundStyle(d.macros.kcal > goalKcal ? Color.red : Color.orange)
                        }
                        RuleMark(y: .value("Objetivo", goalKcal))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                            .foregroundStyle(.secondary)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                    .frame(height: 200)
                    .padding(.vertical, 8)
                }

                Section("Media diaria (días con registros)") {
                    LabeledContent("Calorías", value: "\(fmt(average.kcal)) kcal")
                    LabeledContent("Proteína", value: "\(fmt(average.protein)) g")
                    LabeledContent("Carbohidratos", value: "\(fmt(average.carbs)) g")
                    LabeledContent("Grasas", value: "\(fmt(average.fat)) g")
                }

                Section("Por día") {
                    ForEach(totals.reversed()) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(d.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                Spacer()
                                Text("\(fmt(d.macros.kcal)) kcal").monospacedDigit()
                            }
                            Text("P \(fmt(d.macros.protein)) · C \(fmt(d.macros.carbs)) · G \(fmt(d.macros.fat))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Historial")
        }
    }
}
