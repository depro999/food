import SwiftUI

/// Guía para pasar los datos a Apple Salud con la app Atajos.
struct ShortcutsHelpView: View {
    var body: some View {
        Form {
            Section {
                Text("La app no escribe en Apple Salud directamente. Ofrece acciones para Atajos que devuelven los totales de un día, y el propio Atajos los registra en Salud con su acción «Registrar muestra de salud».")
                    .font(.callout)
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("Abrir Atajos", systemImage: "arrow.up.forward.app")
                }
            }

            Section("Cómo crear el atajo") {
                step(1, "En Atajos, crea un atajo nuevo.")
                step(2, "Añade «Fecha actual» y, si quieres exportar ayer, «Ajustar fecha» (−1 día). Así el día ya está completo.")
                step(3, "Busca esta app y añade «Obtener nutriente de un día». Elige el nutriente (p. ej. Proteína) y, en «Día», la fecha del paso anterior.")
                step(4, "Añade «Registrar muestra de salud». Tipo: el mismo nutriente; Valor: el resultado del paso 3; Unidad: la de la tabla de abajo; Fecha: la misma del paso 2.")
                step(5, "Repite 3 y 4 para Calorías, Carbohidratos, Grasas y los micronutrientes que quieras llevar a Salud.")
                step(6, "Opcional: crea una Automatización diaria (p. ej. 00:05) que ejecute el atajo, sin preguntar antes.")
            }

            Section {
                Text("Ejecuta el atajo una sola vez por día: Salud no detecta duplicados y sumaría los valores dos veces.")
                    .font(.footnote)
                Text("Si un nutriente da 0, puedes saltarte su registro con una acción «Si».")
                    .font(.footnote)
            } header: {
                Text("Ojo")
            }

            Section {
                Text("• «Exportar la comida de un día (texto)»: resumen legible por comidas.")
                Text("• «Exportar la comida de un día (CSV)»: archivo con un alimento por fila y todos los micronutrientes, para guardar en Archivos o compartir.")
            } header: {
                Text("Otras acciones")
            }
            .font(.footnote)

            Section {
                HStack {
                    Text("Calorías"); Spacer()
                    Text("kcal").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Proteína, carbohidratos, grasas"); Spacer()
                    Text("g").foregroundStyle(.secondary)
                }
                ForEach(Nutrient.allCases) { n in
                    HStack {
                        Text(n.title); Spacer()
                        Text(n.unit.symbol).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Unidad que devuelve cada nutriente")
            } footer: {
                Text("Los tipos disponibles en «Registrar muestra de salud» dependen de tu versión de iOS.")
            }
        }
        .navigationTitle("Atajos y Salud")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.callout.bold()).frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.2), in: Circle())
            Text(text).font(.callout)
        }
    }
}
