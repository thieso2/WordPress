# language: en
# spec-id: PT-S013
# traceability:
#   screen: web.search (SCR-0139)
#   legacy_origin: wp-includes/template-loader.php -> search
#   screen_mode: literal (screen_modernization_decision.md, hybrid)
#   golden: _reversa_sdd/screens/golden/manifest.yaml
#   deviations: DEV-001 (capture pending), DEV-005 (token systems)
#
# BLOCKED: manifest.yaml reports present:false for this screen. Per the Screen
# Translator's literal-mode edge case the scenario is emitted anyway, but
# validation is MANUAL until the capture runs against the Wave 0 oracle.
# DEV-001 is approved CONDITIONALLY on that capture; remove the exception once
# present:true.

Feature: Visual parity for web.search
  As the system
  I want this template's rendered output to match the legacy oracle
  So that front-end fidelity is demonstrated rather than asserted

  # Non-deterministic per manifest.yaml: relevance ordering is MySQL-specific
  # and PostgreSQL ranking will differ regardless of seeding. Compare the result
  # SET and the page chrome, not the ordering.
  @visual-parity @parity
  Scenario: Rendered output matches the golden capture
    Given the parity oracle seeded with the agreed corpus
    And a golden capture of "web.search" taken from the oracle
    When the target renders the route "/?s=sample"
    Then the rendered output matches the golden capture
    And the comparison applies only the normalization rules declared in the manifest

  @visual-parity @invariant
  Scenario: Design tokens resolve from the theme token system
    Given the target renders the route "/?s=sample"
    Then colour, spacing and typography resolve to theme token custom properties
    And no colour, spacing or typography value appears as a loose literal

  @visual-parity
  Scenario: The capture is deterministic
    Given the oracle runs with the injected clock and fixed seed from the manifest
    When "web.search" is captured twice
    Then both captures are byte-identical
