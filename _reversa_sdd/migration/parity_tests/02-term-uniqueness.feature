# language: en
# spec-id: PT-002
# traceability:
#   process_flows: _reversa_sdd/flowcharts/taxonomy-and-terms.md
#   target_architecture: BC-02 Classification (AGG-Term)
#   target_paradigm: classic OO / Active Record
#   rules: BR-MIGRATE-052..064
#
# Paradigm note: implication 3. wp_insert_term() inserts rows, queries for an older
# duplicate, then DELETES ITS OWN ROWS (F-TAX-02). AD-05 replaces that whole dance
# with one unique index. These scenarios prove the constraint, not the dance.

Feature: Classifying content with terms
  As an editor
  I want terms to be unique and hierarchically sane
  So that classification cannot silently duplicate or loop

  @parity @critical
  Scenario: Creating a term in a taxonomy
    Given a hierarchical taxonomy "category"
    When an editor creates the term "News" with slug "news"
    Then the term exists in that taxonomy
    And the term's content count is 0

  # F-DD-05: the legacy schema's ONLY semantic unique key is (term_id, taxonomy),
  # which does NOT cover the case wp_insert_term() actually guards.
  @parity @invariant
  Scenario: A duplicate slug within the same taxonomy and parent is rejected by the database
    Given a term "News" with slug "news" and no parent in taxonomy "category"
    When a second term with slug "news" and no parent in taxonomy "category" is written directly to the database
    Then the write is rejected by a uniqueness constraint

  @parity @invariant
  Scenario: The same slug is permitted under a different parent
    Given a term "Sport" with slug "sport" and no parent in taxonomy "category"
    And a term "Local" with slug "local" and no parent in taxonomy "category"
    When an editor creates a term with slug "sport" whose parent is "local"
    Then the term is created successfully

  # BR-TAX-13. The legacy needs a RUNTIME ancestor cycle guard because nothing
  # in the schema prevents a loop. The target prevents it structurally.
  @parity @invariant
  Scenario: A term cannot become its own ancestor
    Given a term "Parent" and its child "Child"
    When an editor attempts to set "Parent" as a child of "Child"
    Then the change is rejected
    And the hierarchy is unchanged

  # BR-TAX-11 + F-TAX-05. The legacy pads counts at READ time by joining
  # term_relationships to posts filtered on post_status='publish' — on every render.
  # The target keeps a counter cache. The BEHAVIOUR under test is which records count.
  @parity @critical
  Scenario: Term counts include published records only
    Given a term "News"
    And a published record classified under "News"
    And a draft record classified under "News"
    And a trashed record classified under "News"
    Then the term's content count is 1

  @parity
  Scenario: Unpublishing a record decrements the term count
    Given a term "News" with exactly one published record classified under it
    When that record moves to status "draft"
    Then the term's content count is 0

  # Surviving edge direction: Classification READS Publishing, never the reverse.
  # target_architecture.md BC-02. If this direction ever inverts, the legacy
  # posts-taxonomy cycle is back.
  @parity @invariant
  Scenario: Deleting a record removes its classifications
    Given a published record classified under two terms
    When the record is deleted
    Then no classification assignments reference that record
    And both terms' counts are decremented
