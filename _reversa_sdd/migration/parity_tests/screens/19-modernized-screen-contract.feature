# language: en
# spec-id: PT-S019
# traceability:
#   screens: all 123 in-scope modernized screens (console.*, auth.*, tenancy.*)
#   screen_mode: modernized (screen_modernization_decision.md, hybrid)
#   target_screens: target_screens.md Parts 3, 4, 5, 6
#   deviations: DEV-002, DEV-003, DEV-004, DEV-005, DEV-006, DEV-008, DEV-009, DEV-010, DEV-011
#
# ############################################################################
# Modernized mode means SEMANTIC CONTRACT ONLY. There is no byte-for-byte or
# visual comparison for these screens, and a visual diff on a console screen is
# NOT a parity failure and must not be reported as one.
#
# One file rather than 123: target_screens.md establishes that ~92 of these are
# instances of two patterns. The contract is asserted against the PATTERN and
# against each screen's declared instantiation.
# ############################################################################

Feature: Modernized screen contracts
  As the system
  I want each modernized screen to honour its declared contract
  So that redesign does not quietly drop information or flow

  @screen-contract @parity @critical
  Scenario: Every modernized screen declares all four states
    Given a screen specified in modernized mode
    Then it declares an idle state
    And it declares a loading state
    And it declares an error state
    And it declares a success state

  # PRINCIPLE 2 — the strongest contract in this file. Textual content is in
  # parity scope for EVERY screen in BOTH modes, so a string diff is a real
  # failure regardless of mode.
  @screen-contract @parity @critical
  Scenario: Functional text is preserved byte-for-byte from the legacy
    Given a screen whose legacy origin declares labels, prompts, validation messages and errors
    When the target screen is rendered
    Then every such string is byte-identical to the legacy string
    And the comparison ignores only trailing whitespace

  # DEV-009, the ONE exception to the rule above, and deliberately narrow.
  @screen-contract @deviation
  Scenario: Branding and project-identity strings are the only permitted string divergence
    Given a string classified as branding or project identity
    When it diverges from the legacy
    Then the divergence is expected
    And no functional label, prompt, validation message or error string diverges

  @screen-contract @parity
  Scenario: Declared events fire with the declared payloads
    Given a screen declaring a submit event
    When the user completes the declared interaction
    Then the declared event is dispatched
    And its payload matches the declared shape

  @screen-contract @parity
  Scenario: Exit transitions lead where the spec declares
    Given a screen declaring exit transitions
    When each transition is taken
    Then the resulting route matches the declared target

  # DEV-002. Composition is NOT comparable — the legacy registered panels through
  # hooks, which AD-01 removes. Compare resulting FIELDS AND VALUES.
  @screen-contract @deviation
  Scenario: Declared panels expose the same fields as the legacy registered ones
    Given a form screen whose legacy equivalent registered panels through hooks
    When the target screen is rendered
    Then the same fields are present with the same values
    And the panel registry itself is not compared

  # DEV-003.
  @screen-contract @deviation
  Scenario: Exact pagination totals are out of scope where declared estimated
    Given a list screen declaring estimated pagination
    When its total is compared against the oracle
    Then a differing total is not a parity failure
    And the page contents remain in parity scope

  # DEV-004.
  @screen-contract @deviation
  Scenario: A destructive bulk action requires confirmation
    Given a list screen with a destructive bulk action
    When the action is invoked
    Then a confirmation is required before the effect occurs
    And the eventual outcome matches the legacy outcome

  # DEV-011. Five screens have no target at all.
  @screen-contract @deviation
  Scenario: Plugin management screens have no target
    Given the legacy plugin management screens
    Then no target screen exists for them
    And no parity scenario is generated

  # DEV-012 — the ONLY parity specs in this project with no BR-MIGRATE rule
  # behind them. They must not be folded into the rule-level specs.
  @screen-contract @editor-parity @critical
  Scenario: Editor interaction specs are authored from oracle observation
    Given the editor screens console.post, console.post-new and console.site-editor
    Then their interaction specifications are authored by observing the oracle
    And they are tracked separately from the rule-level parity specs
    And their coverage is reported against observed behaviour, not against a rule count

  @screen-contract @editor-parity @critical
  Scenario: The readable half of the editor is specified conventionally
    Given the 115 core block schemas and the 23 block supports
    When the inspector control surface is generated
    Then it is derived from those schemas rather than observed
    And server-side block rendering is covered by rule-level parity
