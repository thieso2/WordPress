# User Stories — AI agent integration

> Derived from `ai-abilities-connectors`, `rest-api`, `http-api`.
> **This is the newest surface in WordPress and has no counterpart in existing documentation**
> (F-AI-05). Confidence: 🟢 CONFIRMED · 🟡 INFERRED

---

## US-AI-01 — An agent discovers what it can do

```gherkin
Given abilities have been registered
When an agent requests GET /wp-json/wp-abilities/v1/abilities
Then only abilities that explicitly opted in are listed                # BR-AI-04
And each carries a label, description, category, input and output JSON Schema

Given an ability was registered without opting in
When the list is requested
Then it is ABSENT — DEFAULT_SHOW_IN_REST is false                      # BR-AI-04
```

🟢 The opposite default to `register_rest_route()`, where an omitted `permission_callback`
makes a route **public** (BR-REST-05). See ADR-012.

---

## US-AI-02 — An agent invokes an ability

```gherkin
Given an agent chooses an ability from the list
When it POSTs to /wp-abilities/v1/abilities/{name}/run
Then input is normalised against the input schema                      # BR-AI-05
And validated against that schema — failure returns 400                # BR-AI-06
And the permission_callback is consulted                               # BR-AI-05
And the execute_callback runs
And the RESULT is validated against the output schema                  # BR-AI-06

Given the callback returns something the output schema forbids
When validation runs
Then the call fails rather than returning unverified data              # F-AI-02
```

🟢 Output validation exists nowhere else in WordPress.

---

## US-AI-03 — Registering an ability safely

```gherkin
Given a plugin registers an ability
When the name lacks a namespace prefix
Then registration FAILS with _doing_it_wrong() and returns null        # BR-AI-01

When the name is already registered
Then registration FAILS — there is NO silent overwrite                 # BR-AI-02

When the category has not been registered first
Then registration FAILS                                                # BR-AI-03
```

🟢 All three are the opposite of `register_post_type()` and `add_filter()`, which overwrite
silently.

---

## US-AI-04 — An ability calls an AI provider

```gherkin
Given an ability uses the bundled PHP AI Client
When it makes a provider request
Then the HTTP goes through WP_AI_Client_Http_Client                    # BR-AI-09
And therefore through wp_http_validate_url()'s SSRF guard              # BR-HTTP-08
And through the site's WP_HTTP_BLOCK_EXTERNAL policy if set            # BR-HTTP-13
```

---

## US-AI-05 — The risk this surface introduces 🟡

```gherkin
Given an ability was written expecting a human caller
And its permission_callback assumes a UI context
When a language model invokes it autonomously
Then permission_callback is the ONLY gate                              # F-AI-04 ⚠️

Given an unauthorized caller sends malformed input
When the pipeline runs
Then input validation fails BEFORE permissions are checked             # BR-AI-07
And the caller learns their input was malformed                        # F-AI-03 ⚠️
```

🟡 Neither is a defect in the implementation; both are consequences of the pipeline order
and of abilities becoming machine-reachable. Recorded for review — see question **Q4**.
