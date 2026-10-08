# Expense-OCR — OCR Expense Tracker & Receipt Parser

Mini-Project 3 · Cross-Platform Mobile App Development (VKU)
Author: **Nguyễn Phan Nhật Quang** — 23IT.B176

A Flutter app that turns a photo of a paper receipt into a saved expense, fully
offline. Google ML Kit reads the text on-device, a regex heuristic engine pulls
out the total, merchant and date, and the user checks the result before it is
stored in SQLite. Spending is shown in an animated donut chart and a weekly bar
chart, both drawn with `CustomPainter`.

## Download

Release APKs: [https://github.com/thiennn20/Expense-OCR/releases/latest](https://github.com/thiennn20/Expense-OCR/releases/latest)

![Screens](docs/screenshots/01_dashboard.png)

## Features

| Area | What it does |
|---|---|
| Camera capture | Live viewfinder (`camera`), flash cycle (off / auto / on / torch), tap-to-focus with focus ring, receipt framing overlay. The still photo is cropped to the frame before OCR. Gallery import and manual entry are also available. |
| On-device OCR | `google_mlkit_text_recognition` (Latin model, bundled in the APK, no network). ML Kit's column blocks are re-merged into visual rows so a label and its value end up on the same line. |
| Heuristic parser | Totals such as `150,000 VND`, `150.000 đ`, `45k`; dates in `DD/MM/YYYY`, `DD-MM-YY`, `YYYY-MM-DD`, `Ngày 07 tháng 10 năm 2026`; merchant from a list of known brands or from the receipt header; category suggestion. Every field has a confidence level. |
| Review screen | Edit every field before saving. Low-confidence fields are flagged, every detected amount is a tap-to-use chip, and the raw recognised text can be expanded. |
| Persistence | `sqflite` table with indexes on date and category. The cropped receipt (≤1600 px) and a 240 px thumbnail are stored in `<app documents>/receipts/`. |
| Charts | Category donut that sweeps in, with tap-to-select slices and a linked legend (week / month / all time). Weekly bar chart with staggered growth, tap tooltips and week navigation. |
| Other | History grouped by day, with search, category filter and swipe-to-delete with undo. Light and dark theme. |

## Build & run

Requirements: Flutter **3.x** (tested on 3.47.6 / Dart 3.13), Android SDK 36,
JDK 17. You need a physical Android device or an emulator with a camera
(ML Kit does not run on desktop or web).

```bash
git clone https://github.com/thiennn20/Expense-OCR.git
cd Expense-OCR
flutter pub get

# run on a connected device
flutter run

# unit + widget tests (parser, chart geometry, store, chart interaction)
flutter test

# static analysis
flutter analyze

# release APK -> build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release

# smaller per-ABI APKs
flutter build apk --release --split-per-abi
```

Re-generate the documentation screenshots (rendered from the real widgets with
sample data and a fake camera feed):

```bash
flutter test screenshot_test --update-goldens
```

## Project structure

```
lib/
├── main.dart                     # bootstrap: open DB + image store, inject services
├── core/                         # AppScope (DI), theme, VND formatters, date helpers
├── models/                       # Expense, ExpenseCategory
├── data/
│   ├── expense_repository.dart   # sqflite repository (+ in-memory one for tests)
│   └── receipt_image_store.dart  # crop / resize / thumbnail in a background isolate
├── services/
│   ├── ocr_service.dart          # ML Kit wrapper, timing
│   ├── receipt_layout.dart       # merge ML Kit lines into visual rows
│   ├── receipt_parser.dart       # regex heuristics: total, date, merchant, category
│   ├── receipt_scanner.dart      # pipeline: image → OCR → parse → draft expense
│   └── text_utils.dart           # Vietnamese diacritic folding, OCR digit repair
├── state/expense_store.dart      # ChangeNotifier store + aggregates for the charts
└── ui/
    ├── screens/                  # home shell, dashboard, history, camera, review
    └── widgets/                  # donut & bar CustomPainters, crop overlay, tiles
test/                             # parser, chart math, store and widget tests
screenshot_test/                  # renders docs/screenshots/*.png
docs/                             # technical report + screenshots
```

## Release notes

* `android/app/proguard-rules.pro` keeps R8 from failing on the optional
  Chinese, Japanese, Korean and Devanagari ML Kit recognisers, which the plugin
  references as `compileOnly` dependencies.
* The release build is signed with the debug key so it can be sideloaded. For
  a store release, set up your own `signingConfig`.
