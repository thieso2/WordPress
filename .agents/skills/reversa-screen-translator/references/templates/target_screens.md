---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: target_screens
producedBy: screen-translator
mode: literal | modernized | hybrid
sourcePlatform: <slug>
targetPlatform: <slug>
adapter: <adapters/source__target>
screenCount: <int>
hash: "sha256:<hash of the body below the front-matter>"
---

# Target Screens

> An executable specification of each screen of the new system, derived from the legacy one according to the mode approved in `screen_modernization_decision.md`. Textual content is preserved literally, unless copy editing was explicitly approved.
> Primary reading for the coder. Every section is a contract.

## Summary

- **Mode applied**: <literal | modernized | hybrid>
- **Screens generated**: <N>
- **Adapter**: <slug>
- **Tokens consumed**: see `_reversa_sdd/design-system/tokens.md` and `tokens-derived.md` where applicable
- **Golden files**: <N> in `_reversa_sdd/screens/golden/` (the manifest is in `golden/manifest.yaml`)
- **Deviations recorded**: <N> in `screen_deviation_log.md`

> If the legacy system has no UI (a batch system / API / daemon), replace this section with:
> "No screen detected. Agent skipped in `skipped` mode. Next agent: Inspector."

---

## Screen: <canonical-name>

**Origin**: `<legacy-file>:<line-or-paragraph>`
**Mode applied**: literal | modernized
**Design-system components**: [<token1>, <token2>, ...]
**Interpolation points**: `{{var1}}`, `{{var2}}`
**Exit transitions**: [<the next screen or event>]
**Is it a critical screen?**: yes | no (consult `reversa-detective` when available)

### Specification

> The block below varies with the source→target pair and the mode. See `references/adapter-pairs.md` for each pair's canonical format. Examples below.

#### Example: COBOL TUI → Go CLI/TUI (literal)

```yaml
spec.kind: ansi-byte-stream
spec.normalize:
  - trim_trailing_spaces: false
  - line_endings: "\n"
spec.lines:
  - bytes: "\x1b[96m╔══════════════════════════════════════════════════╗\x1b[0m\n"
  - bytes: "\x1b[96m║                \x1b[93m▓▓▓  BANCO ATM  ▓▓▓\x1b[96m               ║\x1b[0m\n"
  - bytes: "\x1b[96m║                  \x1b[97m{{header_subtitle}}\x1b[96m                ║\x1b[0m\n"
    interpolations:
      header_subtitle:
        type: string
        max_width: 16
        source: literal "Cash Machine" | literal "System Access"
  - bytes: "\x1b[96m╚══════════════════════════════════════════════════╝\x1b[0m\n"
spec.input_prompts:
  - kind: accept-line
    prompt_bytes: "   \x1b[96m>>\x1b[97m Select an option: \x1b[0m"
    captures: option
    valid: ["0", "1", "2", "3", "4", "5"]
```

#### Example: Win32/Delphi VCL → Web SPA (modernized)

```yaml
spec.kind: component-tree
spec.states: [idle, loading, error, success]
spec.root:
  component: PageLayout
  variant: form
  children:
    - component: Header
      tokens: [color.brand-primary, typography.h1]
      content:
        text: "Customer Registration"
    - component: Form
      submit_event: customer.create
      children:
        - component: FormField
          name: name
          label: "Full name"
          legacy_origin: "TForm1.edtNome"
          validation:
            required: true
            max_length: 80
        - component: FormField
          name: tax_id
          label: "Tax ID"
          legacy_origin: "TForm1.mskCPF"
          mask: "999.999.999-99"
          validation:
            required: true
            tax_id: true
    - component: ButtonRow
      children:
        - component: Button
          variant: primary
          label: "Save"
          legacy_origin: "TForm1.btnSalvar"
          action: form.submit
        - component: Button
          variant: ghost
          label: "Cancel"
          legacy_origin: "TForm1.btnCancelar"
          action: navigate.back
spec.state_messages:
  loading: "Saving..."
  error: "{{error_message}}"
  success: "Customer registered successfully."
```

#### Example: server-rendered legacy HTML → a componentized SPA (modernized)

```yaml
spec.kind: route-component
spec.route: /customers/new
spec.layout: AppLayout
spec.states: [idle, loading, error, success]
spec.component:
  component: CustomersNewPage
  legacy_origin: "/admin/cliente_novo.asp"
  state:
    customer:
      type: Customer
      initial: empty
  children:
    - component: PageTitle
      content: "New Customer"
    - component: CustomerForm
      props:
        onSubmit: customerService.create
        initial: $state.customer
spec.api_changes:
  - legacy: POST /admin/cliente_novo.asp (form-urlencoded)
    target: POST /api/customers (application/json)
    deviation: DEV-014
```

#### Example: Android XML → Flutter (modernized)

```yaml
spec.kind: composable
spec.name: CustomerListScreen
spec.legacy_origin: "app/src/main/res/layout/activity_cliente_list.xml + ClienteListActivity.java"
spec.states: [idle, loading, error, success]
spec.composable: |
  Scaffold(
    appBar: AppBar(title: Text("Customers")),
    body: Consumer<CustomerListVM>(
      builder: (ctx, vm, _) => vm.loading
        ? CircularProgressIndicator()
        : ListView.builder(
            itemCount: vm.customers.length,
            itemBuilder: (_, i) => CustomerListTile(customer: vm.customers[i]),
          ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => Navigator.pushNamed(ctx, '/customers/new'),
      child: Icon(Icons.add),
    ),
  )
spec.viewmodel:
  name: CustomerListVM
  legacy_origin: "ClienteListActivity.onResume"
  methods:
    - load(): calls customerService.list
```

### Accepted points of divergence

- DEV-XXX: <short description> (see `screen_deviation_log.md#DEV-XXX`)

### States (modernized mode only)

| State | Description | Content / message |
|---|---|---|
| Idle | The default state before any action | <content> |
| Loading | An asynchronous operation in progress | <spinner / skeleton> |
| Error | A failed operation or invalid data | `{{error_message}}` |
| Success | The operation completed successfully | <confirmation message> |

> In literal mode, this section can be omitted or replaced with "preserves the legacy system's states" if the legacy system has no explicit state handling.

---

## Screen: <second-screen>

(repeat the block above for each screen)

---

## Appendix: traceability to the inventory

| Screen in `target_screens.md` | Origin in `_reversa_sdd/ui/inventory.md` | Origin in `_reversa_sdd/screens/inventory.json` |
|---|---|---|
| <screen 1> | <inventory line> | <internal inventory id> |
| <screen 2> | <inventory line> | <internal inventory id> |
