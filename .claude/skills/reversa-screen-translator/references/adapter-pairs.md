# Adapter Pairs

A map of the source→target pairs supported in v1, with the default recommended mode and the canonical spec format to use in `target_screens.md`. Pairs not listed return `EC-01` and offer the raw template.

## Master table

| Source | Target | Recommended mode | Adapter | Spec format |
|---|---|---|---|---|
| `cobol-ansi-tui` | `go-cli` | literal | `cobol_ansi__go_cli` | `ansi-byte-stream` |
| `cobol-ansi-tui` | `rust-cli` | literal | `cobol_ansi__rust_cli` | `ansi-byte-stream` |
| `cobol-ansi-tui` | `web-spa` | modernized | `cobol_ansi__web_spa` | `component-tree` |
| `cobol-screen-section` | `go-cli` | literal | `cobol_screen__go_cli` | `ansi-byte-stream` |
| `ncurses-c` | `go-cli` | literal | `ncurses__go_cli` | `ansi-byte-stream` |
| `ncurses-c` | `rust-cli` | literal | `ncurses__rust_cli` | `ansi-byte-stream` |
| `delphi-vcl` | `web-spa` | modernized | `delphi_vcl__web_spa` | `component-tree` |
| `delphi-vcl` | `tauri` | modernized (with a literal-ish option) | `delphi_vcl__tauri` | `component-tree` |
| `delphi-vcl` | `electron` | modernized | `delphi_vcl__electron` | `component-tree` |
| `delphi-firemonkey` | `flutter` | modernized | `delphi_firemonkey__flutter` | `composable` |
| `vb6` | `web-spa` | modernized | `vb6__web_spa` | `component-tree` |
| `vb6` | `tauri` | modernized | `vb6__tauri` | `component-tree` |
| `vbnet-winforms` | `web-spa` | modernized | `vbnet_winforms__web_spa` | `component-tree` |
| `csharp-winforms` | `web-spa` | modernized | `csharp_winforms__web_spa` | `component-tree` |
| `csharp-wpf` | `web-spa` | modernized | `csharp_wpf__web_spa` | `component-tree` |
| `win32-mfc` | `web-spa` | modernized | `win32_mfc__web_spa` | `component-tree` |
| `win32-raw` | `web-spa` | modernized | `win32_raw__web_spa` | `component-tree` |
| `asp-classic` | `web-spa` (React/Vue/Svelte) | modernized | `asp_classic__spa` | `route-component` |
| `aspnet-webforms` | `web-spa` | modernized | `aspnet_webforms__spa` | `route-component` |
| `jsp` | `web-spa` | modernized | `jsp__spa` | `route-component` |
| `php-server-rendered` | `web-spa` | modernized | `php__spa` | `route-component` |
| `html-legacy-jquery` | `web-spa` | modernized | `html_legacy__spa` | `route-component` |
| `android-xml-java` | `flutter` | modernized | `android_xml__flutter` | `composable` |
| `android-xml-java` | `compose` | modernized (close idiom) | `android_xml__compose` | `composable` |
| `android-xml-kotlin` | `compose` | modernized (close idiom) | `android_xml_kt__compose` | `composable` |
| `ios-xib-objc` | `flutter` | modernized | `ios_xib_objc__flutter` | `composable` |
| `ios-xib-objc` | `swiftui` | modernized (close idiom) | `ios_xib_objc__swiftui` | `composable` |
| `ios-xib-swift` | `swiftui` | modernized (close idiom) | `ios_xib_swift__swiftui` | `composable` |

## Available modes per pair

For each pair, three modes are generally presented to the user, but some combinations make literal mode **unviable**. The table below narrows it down.

| Pair | Is literal viable? | Why |
|---|---|---|
| `cobol-ansi-tui` → `go-cli` | yes | textual terminals honor ANSI byte for byte |
| `cobol-ansi-tui` → `web-spa` | no | a terminal has no literal DOM equivalent; literal mode is refused |
| `delphi-vcl` → `web-spa` | partial | only with a legacy screenshot and an explicit acceptance; pixel-perfect is rare |
| `win32-mfc` → `web-spa` | no | literal mode refused; modernized recommended |
| `android-xml-*` → `flutter` | partial | only with per-density screenshots; pixel-perfect depends on the font |
| `android-xml-*` → `compose` | partial | the same idiom, closer, but the widgets diverge |
| `ios-xib-*` → `swiftui` | partial | the same platform, but constraints and auto-layout diverge |

When `literal` is not viable, the agent presents only modernized and hybrid as options, and explains to the user why literal was ruled out.

## Spec format per kind

### `ansi-byte-stream` (textual terminals)

Each line as a `bytes` block containing the literal sequence, including ANSI escapes. Use `\x1b[...m` for colors. Interpolations declared with `interpolations.<name>` per line. User inputs via `spec.input_prompts`.

The typical target implementation: one function per screen in `pkg/menu/screens.<ext>` writing to an `io.Writer`.

### `component-tree` (graphical desktop/web/mobile, modernized mode)

A hierarchy of named components (`PageLayout`, `Form`, `FormField`, `Button`, ...). Tokens referenced in `tokens: [...]`. Events in `submit_event`, `action`. States in `spec.states: [idle, loading, error, success]`. Per-state messages in `spec.state_messages`.

The target implementation: any framework (React, Vue, Svelte, SwiftUI, Compose, a Tauri webview, etc.) unless `target_architecture.md` has already pinned a specific one.

### `route-component` (modernized web from server-rendered)

Includes `spec.route` (the target's canonical URL) and `spec.layout` (the parent layout). The body is a `component-tree`. `spec.api_changes` lists HTTP contract changes between the legacy system and the target (URL, method, content-type), referencing deviations.

### `composable` (cross-platform mobile)

A `spec.composable` block with declarative pseudo-code in the target's idiom (Flutter Dart, Compose Kotlin, SwiftUI Swift). It includes `spec.viewmodel` when the target separates view and state.

### `raw-prose` (the EC-01 fallback)

When no adapter covers the pair. The content is structured prose with mandatory sections (identity, layout, fields, messages, events, validations). Every screen in `raw-prose` must have a recorded deviation noting that the coder will need to interpret the prose.

## Special inputs and states

Every spec, in any kind, may include:

- `spec.normalize`: the rules accepted when comparing against a golden file (line endings, trailing spaces, ANSI trimming, etc.).
- `spec.interpolations`: the points where dynamic domain data enters (e.g. `{{holder}}`, `{{balance}}`). With types and constraints (max_width, regex, lookup).
- `spec.transitions`: the list of events that lead to another screen.
- `spec.legacy_origin`: a `file:line` or `file:paragraph` path in the legacy system.
- `spec.deviations`: the `DEV-XXX` ids that affect the screen.

## Pairs not covered in v1

- Platforms with custom rendering (HTML5 Canvas, OpenGL, games): they return `EC-01`.
- 3D, AR/VR: out of scope (NG-07).
- Voice / conversational: out of scope.
- Discontinued embedded plugins (Crystal Reports, Flash, ActiveX): handled in v2 (OQ-03).

New pairs can be added as rows in this table, along with a descriptive adapter (not code; it is the textual heuristic the agent uses to generate the spec).
