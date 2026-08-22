# language: en
# spec-id: PT-007
# traceability:
#   process_flows: _reversa_sdd/flowcharts/query-and-loop.md
#   target_architecture: BC-09 Routing (AGG-Permalink)
#   target_paradigm: classic OO / Active Record
#   rules: BR-MIGRATE-141..152; coupling BR-POST-07 / F-RW-06
#
# ############################################################################
# This flow covers the ONE cycle edge that genuinely SURVIVES the paradigm change.
#
# topology_decision.md: most of the legacy's 23-module cycle dissolves with the
# hook system and the boot globals. Routing <-> query does not. The pagination
# base and the registered feed slugs determine WHICH POST SLUGS ARE LEGAL, and
# that is a real coupling that must be MODELLED DELIBERATELY rather than inherited.
#
# It is also invisible from either module alone (F-SIM-05), which is why it gets
# its own feature file instead of living inside PT-001.
# ############################################################################

Feature: Permalinks, reserved segments and slug allocation
  As the system
  I want slug allocation to know which route segments are reserved
  So that a published record can never shadow a route

  @parity @critical
  Scenario: The reserved segment set is derived from the permalink structure
    Given a permalink structure containing a pagination base and registered feed slugs
    When the reserved segment set is computed
    Then it contains the pagination base
    And it contains every registered feed slug
    And it contains the embed segment

  # BR-POST-07 / F-RW-06. The coupling under test.
  @parity @critical
  Scenario Outline: A slug matching a reserved segment is refused and suffixed
    Given the reserved segment "<segment>"
    When an author publishes a record requesting the slug "<segment>"
    Then the allocated slug is not "<segment>"

    Examples:
      | segment |
      | page    |
      | feed    |
      | embed   |

  @parity
  Scenario: A slug that is purely a pagination number is refused
    Given the pagination base is "page"
    When an author publishes a record requesting the slug "2"
    Then the allocated slug takes a numeric suffix

  # AD-06: the compiled route table is DERIVED STATE. In the legacy it is a single
  # autoloaded option that can silently exceed the 150 KB threshold and
  # de-autoload the entire router (BR-OPT-06, F-RW-02).
  @parity @invariant @critical
  Scenario: Changing the permalink structure recomputes the reserved set and the route table
    Given a published record with slug "page-2"
    When the permalink structure is changed so that "page-2" would shadow a route
    Then the route table is recomputed
    And the conflict is surfaced rather than silently resolved

  @parity @invariant
  Scenario: The compiled route table is never stored as a setting
    Given the settings store
    Then it contains no compiled route table
    And it contains no scheduled-work queue

  # Replaces the legacy _wp_old_slug / _wp_old_date postmeta pair (AD-03).
  @parity
  Scenario: Changing a published record's slug records a redirect from the old path
    Given a published record with slug "original"
    When the slug is changed to "renamed"
    Then a redirect exists from the old path to the record
    And requesting the old path resolves to the record
