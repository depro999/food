# Macros — contador de macros para iOS (SwiftUI + SwiftData)

**Requisitos:** Xcode 15+, iOS 17+. Todo en Swift, sin dependencias externas.

## Funciones
- 📷 Escáner de códigos de barras (EAN/UPC/Code128…) y QR con AVFoundation.
- 🥫 Base de datos: **Open Food Facts** (gratuita, abierta, sin API key, muy buena cobertura en España).
- 🔎 Búsqueda por nombre/marca y entrada manual de código.
- ✨ Foto del plato → la IA (Claude, visión) detecta alimentos, estima gramos y macros; puedes ajustar gramos.
- 📊 Diario por comidas, anillo de calorías, barras de macros, historial de 7 días (Swift Charts).
- 🔁 **Recetas y comidas recurrentes**: guarda una receta (varios alimentos) y repítela los días que quieras (lunes, martes, L–V…). Se añade sola al diario o aparece como pendiente en «Hoy». También puedes guardar una comida del diario como receta desde el menú ⋯ de cada comida.
- 🎯 Objetivos personalizables. Datos guardados en el dispositivo con SwiftData.

## Cómo abrirlo en Xcode
### Opción A (recomendada): XcodeGen
```bash
brew install xcodegen
cd MacroTracker
xcodegen generate
open MacroTracker.xcodeproj
```
Cambia el `bundleIdPrefix` en `project.yml` y selecciona tu Team en *Signing & Capabilities*.

### Opción B: manual
1. Xcode → New Project → iOS App (SwiftUI, Storage: None), nombre `MacroTracker`, iOS 17.
2. Borra `ContentView.swift` y el `App` generados y arrastra la carpeta `Sources/` al proyecto.
3. En *Info* añade la clave `NSCameraUsageDescription` (Privacy - Camera Usage Description).

## Configurar la IA
Ajustes → pega tu API key de Anthropic (console.anthropic.com). Se guarda en el Llavero.
El modelo por defecto es `claude-sonnet-5-5` (editable en Ajustes).

> ⚠️ Para producción, no distribuyas la API key dentro de la app: crea un pequeño backend
> que reciba la foto y llame a la API. Solo tendrías que cambiar la URL y las cabeceras en
> `AIFoodRecognizer.swift`.

## Notas
- El simulador no tiene cámara: usa el campo "Código manual" (p. ej. `3017620422003`) y la galería.
- Las cifras de la IA son estimaciones; ajusta los gramos si conoces el peso real.
- Open Food Facts pide un User-Agent identificable: edítalo en `OpenFoodFactsService.swift`.

## Estructura
```
Sources/
├─ MacroTrackerApp.swift
├─ Models/Models.swift                 (Macros, FoodItem, FoodEntry @Model)
├─ Services/OpenFoodFactsService.swift (búsqueda + código de barras)
├─ Services/AIFoodRecognizer.swift     (foto → macros con IA)
├─ Services/KeychainStore.swift
├─ Services/RecipeScheduler.swift      (aplica las recetas recurrentes)
└─ Views/ (Recipes, Today, AddFood, FoodDetail, BarcodeScanner, PhotoAnalysis, History, Settings)
```
