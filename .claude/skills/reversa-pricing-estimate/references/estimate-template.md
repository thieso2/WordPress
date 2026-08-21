# estimate.md template

This is the Markdown template the `reversa-pricing-estimate` agent uses to generate `_reversa_sdd/_pricing/<feature>/estimate.md`. Replace every `<placeholder>` with the real value. Keep the structure fixed.

```markdown
# Price Estimate

**Feature:** `<relative_feature_dir>`
**Generated at:** <created_at_local_readable>
**Calculation versions:** Effort v<effort_formula_version>, Value v<value_formula_version>, Market v<market_table_version>

**Prerequisites consumed:**
- Profile: `<output_folder>/_pricing/profile.json`
- Size: `<output_folder>/_pricing/<feature>/size.json` (class `<complexity_class>`, auxiliary score `<size_score>`)

## Overview

| Scenario | Range | Comment |
|---|---|---|
| **Effort** | <effort_str> | <hours_min> to <hours_max>h, cost + tax + markup |
| **Value** | <value_str> | 10% to 30% of the declared annual value |
| **Market Range** | <market_str> | sourced hourly rate per country and seniority |

## Effort scenario

**What it is:** a price computed from likely hours, the hourly rate, an approximate tax reserve and the project markup. It is the defensible floor that stops you from subsidizing the client.

**When to use it:** always, as a sanity check. Charging below Effort means taking a loss or squeezing the project's profit too far.

| Item | Value |
|---|---|
| Complexity class | <complexity_class> |
| Seniority | <seniority> |
| Seniority factor | <seniority_factor> |
| Estimated hours | <hours_min> to <hours_max> h |
| Midpoint | <hours_estimated> h |
| Hourly rate | <hourly_rate> <currency>/h |
| Direct cost | <direct_cost_min> to <direct_cost_max> <currency> |
| Approximate tax reserve | <approx_tax_min> to <approx_tax_max> <currency> |
| Project markup (<margin_percent>%) | <markup_applied_min> to <markup_applied_max> <currency> |
| **Effort range** | **<price_min> to <price_max> <currency>** |
| Midpoint | <price_total> <currency> |

<vat_warning_if_applicable>
<billing_currency_block_if_applicable>

## Value scenario

**What it is:** a price based on part of the annual economic value the feature generates or protects for the client. Reversa uses a capture of 10% to 30% of the declared annual value.

**When to use it:** when the client can declare a return, a saving, or the cost of doing nothing.

<if value.available>

| Item | Value |
|---|---|
| Declared monthly return | <monthly_return_declared> <currency> |
| Users impacted | <users_impacted> |
| Cost of doing nothing | <cost_of_not_doing> <currency> |
| Annual value used | <annual_value> <currency> |
| Capture applied | 10% to 30% |
| Recommended price | <price_recommended> <currency> |
| **Value range** | **<price_min> to <price_max> <currency>** |
| Approximate payback | <payback_str> |

<billing_currency_block_if_applicable>

<if NOT value.available>

> **Value scenario unavailable:** <unavailable_reason>

</if>

## Market Range scenario

**What it is:** a range derived from the hourly benchmark per country and seniority, multiplied by the same hour range as the Effort scenario.

**When to use it:** as an external reference. v2 does not multiply by client profile because there is no reliable public dataset for that.

<if market.available>

| Item | Value |
|---|---|
| Country / Seniority | <country_name> / <seniority> |
| Model / Client profile | <pricing_model> / <client_profile> |
| Complexity | <complexity_class> |
| Market hourly rate | <market_hourly_min> to <market_hourly_max> <currency>/h |
| Source kind | <source_kind> |
| Reference year | <source_year> |
| Sources | <sources> |
| **Market range** | **<market_price_min> to <market_price_max> <currency>** |

<if fallback applied>

> Fallback applied: <reason>

</if>

<billing_currency_block_if_applicable>

<if NOT market.available>

> **Market scenario unavailable:** <unavailable_reason>

</if>

## How to choose between the three

<guidance_based_on_the_scenarios>

General heuristic:

1. Client with no clear return: use Effort as the floor and Market as an external reference
2. Client with a high, clear return: prefer Value, with Effort only as the minimum floor
3. Effort above Market: review the profile, the size or the client fit
4. Market above Effort: there is room to raise the markup or improve the proposal

## Disclaimer

The numbers in this estimate are approximations for budgeting guidance, not a guarantee of closing a sale. The tax factor is an approximate reserve, not an exact legal rate. Real tax validation is the responsibility of the user's accountant. The market range is static and based on the sources documented in `market-benchmarks.md`. The return declared by the client in the Value scenario is raw input and is not validated. We recommend adding `_reversa_sdd/_pricing/<feature>/estimate.{md,json}` to `.gitignore` before committing.
```

## Billing currency

When `profile.billing_currency` is filled in, each scenario gets an extra row:

```markdown
| In <billing_currency> | <billing_amount> <billing_currency> (rate: 1 <billing_currency> = <exchange_rate_to_local> <currency>) |
```

## Short comments

| Scenario | Short comment |
|---|---|
| Effort | `<hours_min> to <hours_max>h, cost + tax + markup` |
| Value | `10% to 30% of the declared annual value` or `Unavailable` |
| Market | `sourced hourly rate per country and seniority` or `Unavailable` |
