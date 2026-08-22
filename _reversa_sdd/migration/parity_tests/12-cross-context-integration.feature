# language: en
# spec-id: PT-012
# traceability:
#   process_flows: _reversa_sdd/traceability/spec-impact-matrix.md section 6
#   target_architecture: the whole content core (BC-01..BC-09)
#   target_paradigm: classic OO / Active Record
#   gate: the Wave 3 integration checkpoint (migration_strategy.md, cutover_plan.md)
#
# ############################################################################
# THIS IS THE GATE THE BRIEF'S PRIMARY RISK ASKED FOR.
#
# F-SIM-05: the most consequential couplings in WordPress are INVISIBLE FROM
# EITHER MODULE ALONE. A wave can be individually parity-clean and jointly wrong
# (RISK-016). Every other feature in this directory tests within one context.
# This one deliberately spans them.
#
# The couplings below are taken verbatim from spec-impact-matrix.md section 6.
# Each was found by the Detective as a rule in one module CAUSING a rule in
# another, and none of them appears in the dependency graph.
# ############################################################################

Feature: Cross-context couplings
  As the system
  I want couplings that span contexts to be exercised end to end
  So that a wave that passes in isolation cannot be wrong in combination

  # COUPLING 1 — taxonomy-and-terms -> posts-and-post-types.
  # Term counts include only post_status='publish' (BR-TAX-11), so a STATUS CHANGE
  # in one context silently changes a COUNT in another.
  @parity @critical @integration
  Scenario: A status change in Publishing silently changes a count in Classification
    Given a term with exactly one published record classified under it
    And the term's content count is 1
    When the record's status changes to "draft"
    Then the term's content count is 0
    And no explicit recount was requested by the caller

  # COUPLING 2 — rewrite-and-permalinks -> posts-and-post-types.
  # pagination_base and the registered feed slugs determine which post slugs are
  # LEGAL (BR-POST-07, F-RW-06). Routing configuration constrains Publishing.
  @parity @critical @integration
  Scenario: Routing configuration constrains slug allocation in Publishing
    Given a permalink structure whose pagination base is "page"
    When an author publishes a record requesting the slug "page"
    Then Publishing refuses the requested slug
    And the refusal originates from the routing context's reserved segment set

  # COUPLING 3 — options-and-transients -> rewrite, cron.
  # The 150 KB autoload threshold can silently de-autoload the routing table or
  # the cron queue (BR-OPT-06, F-RW-02, F-CRON-03). AD-06 removes the coupling
  # by removing the shared table — this scenario asserts the removal.
  @parity @critical @integration @invariant
  Scenario: Settings growth cannot disable routing or scheduling
    Given a settings store containing many large eagerly-loaded settings
    When the total eagerly-loaded volume exceeds any historical threshold
    Then route resolution continues to work
    And scheduled work continues to be discovered
    And no setting was silently reclassified

  # COUPLING 4 — comments -> bootstrap-and-load.
  # Whether a disallowed comment became trash or spam depended on
  # EMPTY_TRASH_DAYS (BR-CMT-10). Deviation approved: the coupling is DELETED.
  @parity @critical @integration @deviation
  Scenario: Moderation outcome is independent of retention configuration
    Given a comment matching a disallowed keyword
    When trash retention is configured to zero days
    Then the comment's status is "spam"
    When trash retention is configured to thirty days
    Then the comment's status is still "spam"

  # COUPLING 5 — authentication-and-sessions -> all nonces.
  # Session token destruction invalidates every outstanding nonce (BR-AUTH-15).
  @parity @critical @integration
  Scenario: Destroying a session invalidates authority granted elsewhere
    Given an authenticated user holding an outstanding request token
    And a pending action in another context authorised by that token
    When the user's session is destroyed
    Then the pending action is refused

  # COUPLING 6 — posts-and-post-types -> database-wpdb.
  # Drafts store '0000-00-00 00:00:00' (BR-POST-04), which is WHY NO_ZERO_DATE is
  # stripped from the SQL mode (BR-DB-10, ADR-007). RISK-007: that value is not a
  # valid PostgreSQL timestamp, and NULL replaces it.
  @parity @critical @integration @invariant
  Scenario: The draft date representation does not require a permissive database mode
    Given a draft with no publication instant
    When the draft is stored
    Then its publication instant is null
    And the database requires no permissive date mode to accept it

  @parity @critical @integration
  Scenario: Records with no publication instant sort last, deterministically
    Given a mix of published records and drafts with no publication instant
    When records are listed in descending publication order
    Then records with no publication instant appear last
    And the ordering is stable across repeated queries

  # COUPLING 7 — block-supports -> registration order.
  # Space-concatenated attribute merge means REGISTRATION ORDER affects emitted
  # class order (F-BSUP-01). The target does not reproduce registration order,
  # which is why manifest.yaml normalizes class-attribute token order.
  @parity @integration
  Scenario: Emitted class order does not depend on registration order
    Given a block with several supports contributing classes
    When the block is rendered twice with supports declared in different orders
    Then the rendered output is equivalent under class-token normalisation

  # The gate itself. cutover_plan.md makes this a prerequisite: a wave that is
  # individually parity-clean can still be jointly wrong.
  @parity @critical @integration
  Scenario: The Wave 3 checkpoint exercises every recorded coupling
    Given the set of cross-context couplings recorded in the spec impact matrix
    When the integration checkpoint runs
    Then every coupling has at least one end-to-end scenario
    And no coupling is covered only by a single-context test
