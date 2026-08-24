# language: en
# spec-id: PT-003
# traceability:
#   process_flows: _reversa_sdd/flowcharts/comments.md
#   target_architecture: BC-03 Discussion (AGG-Comment)
#   target_paradigm: classic OO / Active Record
#   rules: BR-MIGRATE-065..078
#
# THREE of this flow's rules are approved DEVIATIONS — the target deliberately
# does NOT reproduce the legacy. Each is tagged @deviation and states both sides.

Feature: Moderating discussion
  As a moderator
  I want comments admitted only after a recorded verdict
  So that moderation decisions are auditable and consistent

  @parity @critical
  Scenario: A comment from a previously approved author is admitted
    Given moderation requires previous approval
    And an author with a previously approved comment
    When that author submits a comment
    Then the comment's status is "approved"
    And a moderation verdict is recorded with its reason

  @parity @critical
  Scenario: A comment exceeding the configured link limit is held
    Given the maximum link count is 2
    When a comment containing 3 links is submitted
    Then the comment's status is "pending"
    And the moderation verdict's reason identifies the link limit

  # DEVIATION BR-CMT-04. In the legacy the flood verdict defaults to FALSE, so no
  # rate limit is ever actually enforced. The target enforces one.
  @parity @deviation @critical
  Scenario: Rapid repeat submissions are rate limited
    Given an author who submitted a comment 2 seconds ago
    When that author submits another comment
    Then the submission is rejected as too frequent
    And the legacy behaviour of accepting it is recorded as an accepted divergence

  # DEVIATION BR-CMT-08. The legacy matches disallowed keywords as unquoted
  # SUBSTRINGS across six fields, so "press" matches "WordPress".
  @parity @deviation
  Scenario: Disallowed keywords match on word boundaries
    Given "press" is a disallowed keyword
    When a comment containing the word "WordPress" is submitted
    Then the comment is not marked as spam for that reason
    And the divergence from the legacy substring match is recorded

  # DEVIATION BR-CMT-10. In the legacy, whether a disallowed comment becomes
  # trash or spam depends on EMPTY_TRASH_DAYS — a coupling into bootstrap that
  # nobody would predict from the comments module alone.
  @parity @deviation
  Scenario: A disallowed comment is marked spam regardless of trash configuration
    Given a comment matching a disallowed keyword
    When the comment is submitted
    Then the comment's status is "spam"
    And the outcome does not depend on any trash-retention setting

  # BR-CMT-12, resolved at the Curator pause: a state enum, not a varchar.
  @parity @invariant
  Scenario: An unrecognised status cannot be persisted
    Given a comment in status "pending"
    When a status outside the declared set is written directly to the database
    Then the write is rejected by the column's type constraint

  @parity @invariant
  Scenario: Deleting a record deletes its discussion
    Given a published record with 3 approved comments
    When the record is deleted
    Then no comments reference that record

  @parity
  Scenario: Threading depth is bounded
    Given the maximum threading depth is 5
    When a reply is submitted at depth 6
    Then the reply is rejected or attached at the maximum permitted depth
