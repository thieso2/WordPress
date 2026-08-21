# Platform Detection

The heuristics `reversa-screen-translator` uses to classify the legacy system's source platform from the content of `_reversa_sdd/inventory.md` and the source code. Use it together with `references/adapter-pairs.md` to choose the adapter.

The confidence scale applied per classification:

- 🟢 **CONFIRMED**: at least one strong signature (a header, a namespace, a unique marker) is present.
- 🟡 **INFERRED**: the extension and the general pattern match, but there is no unique signature.
- 🔴 **GAP**: the source-code artifact is missing; the classification comes from `inventory.md` alone.
- ⚠️ **AMBIGUOUS**: two plausible platforms tied (e.g. classic ASP vs ASP.NET WebForms in old projects).

## Signature table

| Source slug | Typical extension | Strong signature | Weak signature |
|---|---|---|---|
| `cobol-ansi-tui` | `.cob`, `.cbl`, `.cpy` | `PROCEDURE DIVISION.` + `DISPLAY`/`ACCEPT` + `\x1B[` sequences, Unicode box-drawing (`╔ ╗ ┌ ┐`) | only `PROCEDURE DIVISION` (no ANSI = COBOL batch) |
| `cobol-screen-section` | `.cob`, `.cbl` | `SCREEN SECTION` + atributos `LINE`, `COLUMN`, `FOREGROUND-COLOR` | `SCREEN SECTION` with no details |
| `ncurses-c` | `.c`, `.h` | `#include <ncurses.h>` ou `<curses.h>` + `WINDOW *`, `wprintw`, `mvwaddstr` | `printf` + `\033[` (a hand-rolled TUI) |
| `delphi-vcl` | `.pas`, `.dfm`, `.dpr` | `unit `, `interface`, `TForm`, `TPanel`, `TButton` em `.dfm` | plain `.pas` with no `.dfm` (likely a CLI) |
| `delphi-firemonkey` | `.pas`, `.fmx` | `TForm` in a `.fmx` file (FireMonkey) | only `.pas` |
| `vb6` | `.frm`, `.bas`, `.cls`, `.vbp` | `VERSION 5.00` no header, `Begin VB.Form`, `Begin VB.CommandButton` | plain `.bas` (a module with no UI) |
| `vbnet-winforms` | `.vb` + `Designer.vb` | `Inherits System.Windows.Forms.Form` | only `Module ... Sub Main` (a CLI) |
| `csharp-winforms` | `.cs`, `.designer.cs` | `using System.Windows.Forms;` + `partial class ... : Form` | only `using System;` |
| `csharp-wpf` | `.xaml`, `.cs` | `xmlns="http://schemas.microsoft.com/winfx/..."` + `<Window>`, `<Grid>` | only `.cs` with no `.xaml` |
| `win32-mfc` | `.cpp`, `.h`, `.rc` | `BEGIN_MESSAGE_MAP`, `CDialog`, `WinMain`, `IDD_*` em `.rc` | a bare `WinMain` |
| `win32-raw` | `.cpp`, `.h` | `WinMain` + `RegisterClass`, `CreateWindow`, `WM_*` mensagens | only `WinMain` |
| `asp-classic` | `.asp`, `.inc` | `<%@ Language=VBScript %>` ou `<%@ Language=JScript %>` + `Response.Write` | `.asp` with no `<%@` |
| `aspnet-webforms` | `.aspx`, `.aspx.cs`, `.aspx.vb` | `<%@ Page Language="C#"`, `runat="server"`, `<asp:` controls | only a plain `.aspx` |
| `jsp` | `.jsp`, `.jspf` | `<%@ page language="java" %>`, `<jsp:`, `<%! %>` | a `.jsp` with only HTML |
| `php-server-rendered` | `.php` | `<?php ... ?>` + HTML inline + `mysql_*` ou `mysqli_*` | only `.php` in an `api/` folder (probably a REST API, not a UI) |
| `html-legacy-jquery` | `.html`, `.htm`, `.js` | `jQuery`/`$.ajax` + server-side form submits, no SPA framework | static HTML (no dynamic JS) |
| `android-xml-java` | `res/layout/*.xml`, `*.java` | `<LinearLayout>`/`<RelativeLayout>`/`<ConstraintLayout>` + `Activity extends`, `setContentView(R.layout...)` | only Java with no `res/layout/` |
| `android-xml-kotlin` | `res/layout/*.xml`, `*.kt` | the same as above + a Kotlin `Activity()` + `setContentView(R.layout...)` | only Kotlin with no `res/layout/` |
| `android-compose` | `*.kt` | `@Composable`, `setContent { ... }` | no `setContent` |
| `ios-xib-objc` | `.xib`, `.m`, `.h`, `.storyboard` | `UIViewController` + a referenced `*.xib` or `*.storyboard` | only `*.m` with no XIB |
| `ios-xib-swift` | `.xib`, `.swift`, `.storyboard` | a Swift `UIViewController` + XIB/Storyboard | only `*.swift` with no XIB |
| `ios-swiftui` | `*.swift` | `View` + `var body: some View`, `App` lifecycle | no `var body` |
| `flutter` | `*.dart`, `pubspec.yaml` | `import 'package:flutter/material.dart'` + `StatelessWidget`/`StatefulWidget` | no `material.dart` |
| `react-class` | `*.jsx`, `*.tsx` | `class ... extends React.Component` + `render()` | only `*.tsx` (probably modern) |
| `react-hooks` | `*.jsx`, `*.tsx` | `function ... ({...}) { return <...>; }` + `useState`, `useEffect` | (not legacy; this is a target) |

## Additional indicators

- **Directory structure**:
  - `forms/`, `Forms/` → Delphi, VB6, .NET WinForms.
  - `views/`, `templates/` → server-side MVC (ASP, JSP, PHP).
  - `app/src/main/res/layout/` → Android.
  - `Storyboard.storyboard` or `*.xib` at the root → legacy iOS.
  - `Pages/` in a Razor project → ASP.NET.
- **Build files**:
  - `*.dpr` (Delphi), `*.vbp` (VB6), `*.csproj` (.NET), `pom.xml`/`build.gradle` (Java/Android), `Podfile` (iOS), `pubspec.yaml` (Flutter).
- **Version strings in comments or headers**: VB6 marks `VERSION 5.00`; Delphi 7 marks `{$OBJECT}`; .NET with `<TargetFramework>net48</TargetFramework>` indicates legacy WinForms.

## When two platforms tie

- **Classic ASP vs ASP.NET WebForms**: `.asp` files with no `.aspx` → classic. `.aspx` + `.asp` in the same project → a project mid-migration; mark it ⚠️ AMBIGUOUS and ask.
- **VB6 vs VB.NET**: `.frm` + `.vbp` → VB6. `.vb` + `.designer.vb` + `.vbproj` → VB.NET WinForms.
- **Delphi VCL vs FireMonkey**: `.dfm` → VCL. `.fmx` → FireMonkey. Both in the project → mark it ⚠️ AMBIGUOUS.
- **Android Java vs Kotlin**: `.java` + `.kt` in the same project → a project mid-migration; classify per individual file.
- **iOS Storyboard vs XIB**: both are supported; treat them as one class (`ios-xib-*`). The difference goes into the capture detail.

## When nothing matches

Record `EC-01` (unknown source platform) and offer the user a "raw" template where they describe the screen in structured prose, with mandatory sections:

- Identity.
- The layout as ASCII art or a screenshot.
- The list of fields / components.
- Literal messages / labels.
- Events and transitions.
- Validations.

The agent then generates `target_screens.md` with `spec.kind: raw-prose` and records in `screen_deviation_log.md` that the screen did not go through an adapter.
