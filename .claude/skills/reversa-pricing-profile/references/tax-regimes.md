# Tax regime catalog

An extensible catalog used by the `reversa-pricing-profile` agent to map the tax regime declared by the user into an approximate `tax_factor`. The factors are illustrative budgeting reserves, not exact legal rates.

## How to read this file

Each regime has:

- `key`: the canonical key written into `profile.json`
- `country`: an ISO 3166-1 alpha-2 code, or `INTL`
- `name`: the friendly name used in the chat
- `tax_factor`: the approximate factor applied on top of the direct cost
- `tax_factor_kind`: `effective_reserve_estimate`, `statutory_proxy` or `not_computed`
- `includes_vat`: whether it combines income/contribution tax with an itemized VAT/IVA/ISS
- `vat_pass_through_warning`: whether the estimate should warn that part of the tax may be passed on to the client
- `tax_factor_source`: a public source or a description of the basis
- `notes`: a short observation for the user

## Mandatory disclaimer

The factors recorded here are illustrative approximations based on public references known as of 2026-05. They do not replace accounting advice. Their accuracy depends on deductions, municipality, revenue bracket, business classification, tax framing, withholdings, international treaties and the rules in force when the invoice is issued.

The agent must repeat the disclaimer during the interview and in the footer of `profile.md`.

## Brazil (BR)

| key | name | tax_factor | tax_factor_kind | includes_vat | vat_pass_through_warning | tax_factor_source | notes |
|---|---|---:|---|---|---|---|---|
| MEI | Microempreendedor Individual (MEI) | 0.06 | effective_reserve_estimate | true | true | Portal do Empreendedor and the public DAS-MEI rules | Simplified reserve. MEI usually has a fixed DAS and a revenue cap. Software activity may need its classification validated. |
| simples_servicos | Simples Nacional, IT services | 0.15 | effective_reserve_estimate | true | true | Receita Federal, Simples Nacional, annexes and factor R | Average reserve. The real rate depends on the annex, RBT12, factor R, ISS and withholdings. |
| lucro_presumido | Lucro Presumido, services | 0.165 | effective_reserve_estimate | true | true | Receita Federal, IRPJ, CSLL, PIS, COFINS and ISS | Combined reserve for services. Validate the municipal ISS and withholdings. |
| autonomo_pf | Self-employed individual, carne-leao | 0.275 | effective_reserve_estimate | false | false | Receita Federal, progressive IRPF and INSS | Reserve for a senior professional. The effective rate varies with deductions and social security contributions. |

## United States (US)

| key | name | tax_factor | tax_factor_kind | includes_vat | vat_pass_through_warning | tax_factor_source | notes |
|---|---|---:|---|---|---|---|---|
| self_employed_1099 | Self-Employed, 1099, sole proprietor | 0.30 | effective_reserve_estimate | false | false | IRS, self-employment tax and federal income tax | Combined reserve. Does not include state tax or specific deductions. |
| s_corp_llc | S-Corp or LLC with an S-Corp election | 0.22 | effective_reserve_estimate | false | false | IRS, payroll tax, reasonable salary and distributions | Simplified reserve. Requires an accountant for the reasonable salary and distributions. |

## Portugal (PT)

| key | name | tax_factor | tax_factor_kind | includes_vat | vat_pass_through_warning | tax_factor_source | notes |
|---|---|---:|---|---|---|---|---|
| pt_simplificado | Category B, simplified regime | 0.21 | effective_reserve_estimate | true | true | Autoridade Tributaria, IRS Category B, IVA and Social Security | Combined reserve. IVA may be itemized and passed on to the client. |
| pt_organizada | Category B, organized accounting | 0.18 | effective_reserve_estimate | true | true | Autoridade Tributaria, organized accounting | Simplified reserve. Real costs may lower the taxable base. |

## Mexico (MX)

| key | name | tax_factor | tax_factor_kind | includes_vat | vat_pass_through_warning | tax_factor_source | notes |
|---|---|---:|---|---|---|---|---|
| mx_resico | Regimen Simplificado de Confianza (RESICO) | 0.10 | effective_reserve_estimate | true | true | SAT, RESICO PF and IVA | Combined reserve. ISR can be low, but IVA may apply depending on the case. |
| mx_actividad_empresarial | Actividad Empresarial y Profesional (PF) | 0.20 | effective_reserve_estimate | true | true | SAT, progressive ISR and IVA | Simplified reserve for an independent professional. |

## International (INTL)

| key | name | tax_factor | tax_factor_kind | includes_vat | vat_pass_through_warning | tax_factor_source | notes |
|---|---|---:|---|---|---|---|---|
| intl_freelance_no_withhold | International freelance, client does not withhold | 0.00 | not_computed | false | false | Depends on the provider's country | The client pays gross. Use the provider's national regime for the real tax. |
| intl_freelance_with_withhold | International freelance, client withholds at source | 0.15 | effective_reserve_estimate | false | false | Bilateral treaties and local rules | The real withholding depends on the treaty and the client's country. |

## Other

| key | name | tax_factor | tax_factor_kind | includes_vat | vat_pass_through_warning | tax_factor_source | notes |
|---|---|---:|---|---|---|---|---|
| other | Other regime, not listed | 0.00 | not_computed | false | false | The user reported an uncatalogued regime | Tax not computed. The estimate must warn that the calculation is left to the accountant. |

## Essential regimes for future regions

Do not enable these countries as covered in the Market scenario without cataloguing their minimum regimes:

| country | essential regimes |
|---|---|
| GB | sole_trader_self_assessment, limited_company |
| DE | freiberufler, gewerbe_einzelunternehmen, gmbh |
| ES | autonomo_estimacion_directa_simplificada, autonomo_estimacion_directa_normal, sociedad_limitada |
| AR | monotributo, responsable_inscripto |
| CO | regimen_simple, regimen_ordinario_persona_natural, sociedad |

Verified official sources:

- UK GOV.UK, sole trader and limited company: https://www.gov.uk/set-up-business/sole-trader.html
- Germany, federal administration portal, tax registration: https://verwaltung.bund.de/leistungsverzeichnis/EN/leistung/99102019120000/herausgeber/HH-S1000020010000009790/region/020000000000
- Spain, Agencia Tributaria, income determination regimes: https://sede.agenciatributaria.gob.es/Sede/irpf/empresarios-individuales-profesionales/regimenes-determinar-rendimiento-actividad.html
- Argentina ARCA, Monotributo: https://www.afip.gob.ar/monotributo/
- Colombia DIAN, Regimen Simple de Tributacion: https://micrositios.dian.gov.co/regimen-simple-tributacion/

## Suggested default regime per country

When the user answers "I don't know", the agent suggests the default below and sets `tax_regime_confidence = "low"`:

| country | suggested default regime |
|---|---|
| BR | simples_servicos |
| US | self_employed_1099 |
| PT | pt_simplificado |
| MX | mx_resico |
| Any other country | no suggestion, ask for an explicit choice |

## How to extend it

1. Add the country's section with the same table
2. Cite a public source
3. Mark whether the factor includes VAT, IVA or an itemized tax
4. Do not call `tax_factor` a legal rate
5. Update the schema if new fields are needed
