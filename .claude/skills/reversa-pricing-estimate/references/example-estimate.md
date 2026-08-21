# Price Estimate

**Feature:** `_reversa_sdd/forward/042-pix-payment`
**Generated at:** 2026-05-06 16:42 UTC
**Calculation versions:** Effort v2.0, Value v2.0, Market v2.0

**Prerequisites consumed:**
- Profile: `_reversa_sdd/_pricing/profile.json`
- Size: `_reversa_sdd/_pricing/042-pix-payment/size.json` (class `L`, auxiliary score `60`)

## Overview

| Scenario | Range | Comment |
|---|---|---|
| **Effort** | 4,800.00 to 12,000.00 BRL | 32 to 80h, cost + tax + markup |
| **Value** | 2,400.00 to 7,200.00 BRL | 10% to 30% of the declared annual value |
| **Market Range** | 3,200.00 to 16,000.00 BRL | sourced hourly rate per country and seniority |

## Effort scenario

**What it is:** a price computed from likely hours, the hourly rate, an approximate tax reserve and the project markup. It is the defensible floor that stops you from subsidizing the client.

**When to use it:** always, as a sanity check. Charging below Effort means taking a loss or squeezing the project's profit too far.

| Item | Value |
|---|---|
| Complexity class | L |
| Seniority | senior |
| Seniority factor | 1.00 |
| Estimated hours | 32 to 80 h |
| Midpoint | 56 h |
| Hourly rate | 100.00 BRL/h |
| Direct cost | 3,200.00 to 8,000.00 BRL |
| Approximate tax reserve | 480.00 to 1,200.00 BRL |
| Project markup (35%) | 1,120.00 to 2,800.00 BRL |
| **Effort range** | **4,800.00 to 12,000.00 BRL** |
| Midpoint | 8,400.00 BRL |

Warning: part of the tax factor may be an itemized tax passed through to the client. Validate it with an accountant.

## Value scenario

**What it is:** a price based on part of the annual economic value the feature generates or protects for the client. Reversa uses a capture of 10% to 30% of the declared annual value.

**When to use it:** when the client can declare a return, a saving, or the cost of doing nothing.

| Item | Value |
|---|---|
| Declared monthly return | 2,000.00 BRL |
| Users impacted | 500 |
| Cost of doing nothing | 5,000.00 BRL |
| Annual value used | 24,000.00 BRL |
| Capture applied | 10% to 30% |
| Recommended price | 4,800.00 BRL |
| **Value range** | **2,400.00 to 7,200.00 BRL** |
| Approximate payback | 1.2 to 3.6 months |

## Market Range scenario

**What it is:** a range derived from the hourly benchmark per country and seniority, multiplied by the same hour range as the Effort scenario.

**When to use it:** as an external reference. v2 does not multiply by client profile because there is no reliable public dataset for that.

| Item | Value |
|---|---|
| Country / Seniority | Brazil / senior |
| Model / Client profile | fixed_scope / small_business |
| Complexity | L |
| Market hourly rate | 100.00 to 200.00 BRL/h |
| Source kind | salary_derived_freelance_estimate |
| Reference year | 2025-2026 |
| Sources | Portal Salario CAGED, Glassdoor Brasil |
| **Market range** | **3,200.00 to 16,000.00 BRL** |

## How to choose between the three

The declared Value produces a lower range than the average Effort. Use Effort as the defensible floor and Market as an external reference. For this client, charge below 4,800 BRL only if there is a clear strategic reason.

General heuristic:

1. Client with no clear return: use Effort as the floor and Market as an external reference
2. Client with a high, clear return: prefer Value, with Effort only as the minimum floor
3. Effort above Market: review the profile, the size or the client fit
4. Market above Effort: there is room to raise the markup or improve the proposal

## Disclaimer

The numbers in this estimate are approximations for budgeting guidance, not a guarantee of closing a sale. The tax factor is an approximate reserve, not an exact legal rate. Real tax validation is the responsibility of the user's accountant. The market range is static and based on the sources documented in `market-benchmarks.md`. The return declared by the client in the Value scenario is raw input and is not validated. We recommend adding `_reversa_sdd/_pricing/<feature>/estimate.{md,json}` to `.gitignore` before committing.
