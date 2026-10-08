# Expense-OCR — OCR Expense Tracker & Receipt Parser

Mini-Project 3 · Cross-Platform Mobile App Development (VKU)
Author: **Nguyễn Phan Nhật Quang** — 23IT.B176

A Flutter app that turns a photo of a paper receipt into a saved expense, fully
offline. Google ML Kit reads the text on-device, a regex heuristic engine pulls
out the total, merchant and date, and the user checks the result before it is
stored in SQLite. Spending is shown in an animated donut chart and a weekly bar
chart, both drawn with `CustomPainter`.

## Download

- [Latest release](https://github.com/thiennn20/Expense-OCR/releases/latest)
- [Download Android APK (v1.0.0 asset)](https://github.com/thiennn20/Expense-OCR/releases/latest/download/Expense-OCR-v1.0.0.apk)

No release has been published yet. These links become available after the first
successful tag workflow. Use **Latest release** as the main download link:
the universal APK is named `Expense-OCR-<tag>.apk`, so the direct link above
only works while the latest release contains `Expense-OCR-v1.0.0.apk`.
For a permanent v1.0.0 link, use
[`Expense-OCR-v1.0.0.apk`](https://github.com/thiennn20/Expense-OCR/releases/download/v1.0.0/Expense-OCR-v1.0.0.apk)
after v1.0.0 has been published. Allow installation from your browser/file manager
when Android prompts you, then install the APK.

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

Requirements: Flutter **3.47.6** (Dart >=3.13.5), Android SDK 36,
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

## Build and publish Android APKs

The [Android workflow](https://github.com/thiennn20/Expense-OCR/actions/workflows/android-release.yml)
uses Ubuntu, Java 17 and Flutter 3.47.6, with Flutter/pub and Gradle caches.
It runs `flutter doctor -v`, `flutter pub get`, the Dart format check,
`flutter analyze` and `flutter test` before building. Failed checks stop the build
and prevent publication. The lockfile must remain unchanged after dependency resolution.

Pull requests into `main` run the same checks and APK builds. In Actions, select
**Android APK and release → Run workflow**, choose a branch and enter a version
such as `v1.0.0` to build without publishing. Manual runs only upload artifacts,
even when the selected ref is a tag. Artifacts are retained for 14 days.

After merging the workflow PR into `main`, publish the first version with:

```bash
git switch main
git pull --ff-only origin main
git tag v1.0.0
git push origin v1.0.0
```

Pushing a `v*` tag triggers checks, both APK builds, artifact upload, then an
official GitHub Release with four APK assets. Use stable `vMAJOR.MINOR.PATCH`
versions; invalid versions fail before building. The tag/input supplies the APK
version name, while `pubspec.yaml` supplies the Android build number. Increase
the build number in `pubspec.yaml` before subsequent releases.

| Flutter output | Artifact / release asset |
|---|---|
| `build/app/outputs/flutter-apk/app-release.apk` | `Expense-OCR-<tag>.apk` (universal) |
| `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | `app-arm64-v8a-release.apk` |
| `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` | `app-armeabi-v7a-release.apk` |
| `build/app/outputs/flutter-apk/app-x86_64-release.apk` | `app-x86_64-release.apk` |

The universal APK is copied before the split build so it remains available.
Build jobs have read-only repository permissions; only the tag-triggered release
job receives `contents: write`. Rerunning a successful tag workflow replaces its
assets and release notes.

### Signing and limitations

The current release build uses **debug signing** for coursework sideloading.
It is **not suitable for Google Play**. Clean runners may create different debug
keys, so a future APK may require uninstalling the previous app, deleting its
local expenses and receipt images. A persistent release keystore should be
configured before production: store the encoded keystore and passwords in
GitHub Secrets, decode the keystore only on the runner and configure the Gradle
release signing configuration there. Never commit `.jks`, `.keystore` or
`key.properties` files; they are ignored throughout this repository.

OCR uses the Latin model and requires Android/iOS, not desktop/web. Results
depend on image quality and receipt layout; always verify the parsed fields.

### Android build configuration

* `android/app/proguard-rules.pro` keeps R8 from failing on the optional
  Chinese, Japanese, Korean and Devanagari ML Kit recognisers, which the plugin
  references as `compileOnly` dependencies.
* The release build is signed with the debug key so it can be sideloaded. For
  a store release, set up your own `signingConfig`.
