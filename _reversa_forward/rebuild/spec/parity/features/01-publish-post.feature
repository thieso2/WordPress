# language: en
# spec-id: PT-001
# traceability:
#   process_flows: _reversa_sdd/flowcharts/posts-and-post-types.md
#   target_architecture: BC-01 Publishing (AGG-Post)
#   target_paradigm: classic OO / Active Record (paradigm_decision.md option 1)
#   rules: BR-MIGRATE-029..039
#
# Paradigm note: derived state moved from inline procedure into the model
# (implication 4). These scenarios assert BEHAVIOUR, never the mechanism —
# per the Inspector contract set in paradigm_decision.md.

Feature: Publishing a content record
  As an author
  I want to publish, schedule and trash content
  So that the publication state always reflects the intended date

  @parity @critical
  Scenario: Publishing with a date more than 60 seconds ahead yields a scheduled record
    Given an author with permission to publish
    And a draft whose publication instant is 90 seconds in the future
    When the author requests publication
    Then the record's status is "scheduled"
    And the record is not visible on the public archive

  @parity @critical
  Scenario: Publishing with a date less than 60 seconds ahead yields a published record
    Given an author with permission to publish
    And a draft whose publication instant is 30 seconds in the future
    When the author requests publication
    Then the record's status is "published"
    And the record is visible on the public archive

  # BR-MIGRATE-029/030. The 60-second threshold was confirmed by the owner as
  # INTENDED product behaviour, not an implementation accident.
  @parity @critical
  Scenario Outline: The publication threshold is exactly 60 seconds
    Given a draft whose publication instant is <offset> seconds in the future
    When the author requests publication
    Then the record's status is "<status>"

    Examples:
      | offset | status    |
      | 59     | published |
      | 60     | scheduled |
      | 61     | scheduled |

  # BR-MIGRATE-032. Drafts carry no slug at all — in the target this is a NULL
  # column, which is what makes the partial unique index expressible.
  @parity
  Scenario: No slug is allocated for a draft
    Given an author creating a new record
    When the record is saved as a draft
    Then the record has no slug
    And no slug uniqueness conflict is raised against any other draft

  # BR-MIGRATE-033. AD-05: this is a UNIQUE INDEX, not a query loop.
  # The legacy enforces it with wp_unique_post_slug()'s one-query-per-attempt loop.
  @parity @invariant
  Scenario: A duplicate slug within the same type and parent is rejected by the database
    Given a published record of type "page" with parent "about" and slug "team"
    When a second record of type "page" with parent "about" and slug "team" is written directly to the database
    Then the write is rejected by a uniqueness constraint
    And exactly one record with that slug, type and parent exists

  # BR-MIGRATE-034 + F-RW-06. The genuine surviving coupling: routing
  # configuration constrains which slugs are legal. See PT-007.
  @parity
  Scenario: A slug colliding with a reserved route segment takes a numeric suffix
    Given the permalink structure reserves the segment "page"
    When an author publishes a record whose requested slug is "page"
    Then the allocated slug is not "page"
    And the allocated slug begins with "page" followed by a numeric suffix

  # BR-MIGRATE-035. The truncation includes the suffix — a boundary the legacy
  # gets right and a naive port would get wrong.
  @parity
  Scenario: A slug is truncated to 200 bytes including its numeric suffix
    Given a requested slug of 200 bytes that already exists
    When the author publishes the record
    Then the allocated slug is at most 200 bytes in total
    And the numeric suffix is present within those 200 bytes

  # BR-MIGRATE-036. AD-01: the legacy fired transition_post_status; the target
  # RECORDS the transition instead of broadcasting it.
  @parity @invariant
  Scenario: Every status change is recorded as a transition
    Given a record in status "draft"
    When the record moves to "published"
    And the record moves to "trashed"
    Then two status transitions are recorded for that record
    And the transitions are ordered draft to published, then published to trashed

  # Replaces the legacy _wp_trash_meta_status / _wp_trash_meta_time postmeta pair (AD-03).
  @parity @invariant
  Scenario: Trash state is all-or-nothing and restores the prior status
    Given a record in status "published"
    When the record is trashed
    Then the record records both a trash instant and its prior status
    When the record is restored
    Then the record's status is "published"

  # DEVIATION BR-POST-10, approved. The legacy seeds guid from the permalink and
  # never updates it, so it becomes a stale URL masquerading as an identifier.
  @parity @deviation
  Scenario: The stable identifier is a UUID generated at creation
    Given a newly created record
    Then the record carries a UUID identifier
    When the record's slug is changed after publication
    Then the UUID identifier is unchanged
