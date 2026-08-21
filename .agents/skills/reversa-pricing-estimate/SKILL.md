---
name: reversa-pricing-estimate
description: 'Combines the billing profile and the size of the active feature to produce three price scenarios side by side: Effort, Value and Market Range. Runs after `/reversa-pricing-profile` and `/reversa-pricing-size`.'
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.1.0"
  framework: reversa
  phase: pricing
  stage: estimate
---

You are REVERSA's feature pricer. Your mission is to cross the user's billing profile with the active feature's structural metrics and produce three educational scenarios in `_reversa_sdd/_pricing/<feature>/estimate.md` and `estimate.json`.

## Principles

1. Always present three scenarios side by side: Effort, Value, Market Range
2. Never deliver a single number as the final answer
3. Explain each model in plain language
4. Full determinism in the calculations
5. Do not give legal, tax or contractual advice
6. Do not query the network, WebSearch or external services
7. Never use em dashes in any text
8. Every write is atomic, tempfile plus rename, UTF-8 without BOM
9. Tolerates a BOM when reading JSON

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder`, default `_reversa_sdd`
2. Load:
   - `agents/reversa-pricing-estimate/references/effort-formula.md`
   - `agents/reversa-pricing-estimate/references/value-formula.md`
   - `agents/reversa-pricing-estimate/references/market-benchmarks.md`
   - `agents/reversa-pricing-estimate/references/estimate-template.md`
   - `agents/reversa-pricing-estimate/references/estimate-schema.json`

## Resolving the active feature

1. Read `.reversa/active-requirements.json` for `feature-dir`
2. If absent, list the features and ask for a numbered choice

## Prerequisites

1. Check `<output_folder>/_pricing/profile.json`
2. Check `<output_folder>/_pricing/<feature>/size.json`
3. If the profile does not exist, fail with: "I couldn't find profile.json. Run `/reversa-pricing-profile` first."
4. If the size does not exist, fail with: "I couldn't find size.json for this feature. Run `/reversa-pricing-size` first."
5. Accept `size.schema_version = "1.1"` as the preferred one. If it comes as `1.0`, warn that the size uses the old formula and recommend recalculating

## Recalculation

If `estimate.md` or `estimate.json` already exists:

1. Compare the estimate's `created_at` with the profile's and the size's
2. Warn if the profile or the size is newer
3. Ask: "An estimate already exists for this feature. Do you want to recalculate it? Y/N"
4. If "N", stop without changes
5. If "Y", rename estimate.md and estimate.json to `.bak.<YYYYMMDD-HHMMSS>`

## Seniority normalization

Use the canonical values:

```
junior
mid
senior
staff_lead
principal
```

Aliases:

```
pleno -> mid
especialista -> staff_lead
staff -> staff_lead
lead -> staff_lead
```

## Scenario 1: Effort

Apply `references/effort-formula.md` v2.

Summary:

```
hours_by_complexity_class_senior:
  S:   4 to 12
  M:   12 to 32
  L:   32 to 80
  XL:  80 to 160
  XXL: 160 to 320

seniority_factor:
  junior:      1.34
  mid:         1.15
  senior:      1.00
  staff_lead:  0.88
  principal:   0.76

hours_min = round(hours_min[class] * seniority_factor)
hours_max = round(hours_max[class] * seniority_factor)
hours_estimated = round((hours_min + hours_max) / 2)

direct_cost_min = hours_min * hourly_rate
direct_cost_max = hours_max * hourly_rate
direct_cost = hours_estimated * hourly_rate

approx_tax_min = direct_cost_min * tax_factor
approx_tax_max = direct_cost_max * tax_factor
approx_tax = direct_cost * tax_factor

markup_applied_min = direct_cost_min * (margin_percent / 100)
markup_applied_max = direct_cost_max * (margin_percent / 100)
markup_applied = direct_cost * (margin_percent / 100)

price_min = direct_cost_min + approx_tax_min + markup_applied_min
price_max = direct_cost_max + approx_tax_max + markup_applied_max
price_total = direct_cost + approx_tax + markup_applied
```

In the text, call `margin_percent` a project markup, not an accounting net margin.

If `vat_pass_through_warning = true`, add the warning: "Part of the tax factor may be an itemized tax passed through to the client. Validate it with an accountant."

## Scenario 2: Value

Run a mini-interview of 3 questions, one at a time:

1. "How much does this feature generate or save per month for the end client, in `<currency>`? Just the number, or 0 if you don't know."
2. "How many end users or clients are impacted by this feature? Just the number, or 0 if you don't know."
3. "What is the estimated cost to the client of not having this feature, in `<currency>`? Just the number, or 0 if you don't know."

Apply `references/value-formula.md` v2:

```
if monthly_return_declared == 0 AND cost_of_not_doing == 0:
  available = false
else:
  annual_value = max(monthly_return_declared * 12, cost_of_not_doing)
  value_capture_min = 0.10
  value_capture_recommended = 0.20
  value_capture_max = 0.30
  price_min = annual_value * 0.10
  price_recommended = annual_value * 0.20
  price_max = annual_value * 0.30
```

If `monthly_return_declared > 0`, compute `payback_months_min` and `payback_months_max`. Explain payback as context, not as a pricing formula.

`users_impacted` appears in estimate.md, but does not enter the numeric calculation.

## Scenario 3: Market Range

Apply `references/market-benchmarks.md` v2:

1. Normalize the seniority
2. Look up the row by `country` and `seniority`
3. If the country is missing, `available = false`
4. Use the same `hours_min` and `hours_max` as the Effort scenario
5. Compute:

```
price_min = hours_min * market_hourly_min
price_max = hours_max * market_hourly_max
```

Include in the JSON:

```
market_hourly_min
market_hourly_max
source_kind
source_year
sources
fallback_applied
```

`client_profile` does not change the price in v2. If the user reported micro_business or enterprise, produce only a qualitative note.

## Foreign currency

If `profile.billing_currency` and `profile.exchange_rate_to_local` are filled in:

1. Keep the main values in `currency`
2. Compute the equivalent values in `billing_currency`
3. Show the rate used: `1 <billing_currency> = <exchange_rate_to_local> <currency>`
4. Warn that the exchange rate is manual and not updated in real time

## Persistence

Write `estimate.json` per `estimate-schema.json`:

```
schema_version = "1.1"
formula_versions = {
  "effort": "2.0",
  "value": "2.0",
  "market": "2.0"
}
created_at
feature_dir
profile_ref
size_ref
currency
billing_currency
exchange_rate_to_local
scenarios.effort
scenarios.value
scenarios.market
guidance
```

Write `estimate.md` following `estimate-template.md`.

## Presentation in the chat

Show:

```
Pricing feature: <feature-dir>

| Scenario | Range | Comment |
|---|---|---|
| Effort | <price_min> to <price_max> <currency> | <hours_min> to <hours_max>h, cost + tax + markup |
| Value | <price_min> to <price_max> <currency> | 10% to 30% of the declared annual value |
| Market | <price_min> to <price_max> <currency> | sourced hourly rate per country and seniority |
```

Unavailable scenarios appear as "unavailable: <reason>".

## How to choose

Produce guidance based on the comparison of the three available scenarios:

1. Client with no clear return: use Effort as the floor and Market as an external reference
2. Client with a high, clear return: use Value as the primary and Effort as the minimum floor
3. Effort above Market: review the profile, the size or the client fit
4. Market above Effort: there is room to raise the markup or the proposal

## Mandatory disclaimer

Include it in the footer of estimate.md:

```
Disclaimer: the numbers in this estimate are approximations for budgeting guidance, not a guarantee of closing. The tax factor is an approximate reserve, not an exact legal rate. Real tax validation is the responsibility of the user's accountant. The market range is static and based on the sources documented in `market-benchmarks.md`. The return declared by the client in the Value scenario is raw input and is not validated. We recommend adding `_reversa_sdd/_pricing/<feature>/estimate.{md,json}` to `.gitignore` before committing.
```

## Final report

1. The absolute paths of `estimate.json` and `estimate.md`, if written
2. The paths of the `.bak` files, if a recalculation happened
3. Unavailable scenarios, if any
4. The suggested next step

Finish with:

> Type **CONTINUE** to proceed with the suggestion above.
