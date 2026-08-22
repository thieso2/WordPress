# language: en
# spec-id: PT-008
# traceability:
#   process_flows: _reversa_sdd/flowcharts/metadata.md
#   target_architecture: BC-01 Publishing (Attribute) + AD-03
#   target_paradigm: classic OO / Active Record
#   rules: BR-MIGRATE-021..028
#
# Paradigm note: AD-03 promotes every CORE-OWNED metadata key to a real column,
# association or table. Only genuinely arbitrary attributes stay key-value.
# F-META-01: one legacy code path serves five entity types, which makes metadata
# a MECHANISM, not a bounded context.

Feature: Record attributes
  As the system
  I want core-owned attributes to be real columns with real constraints
  So that referential integrity is enforced rather than assumed

  # AD-05 / F-META-02: the legacy runs SELECT COUNT(*) then INSERT with NO unique
  # index behind it, so duplicate meta rows exist despite the $unique argument.
  @parity @invariant @critical
  Scenario: A duplicate attribute key for the same record is rejected by the database
    Given a record carrying the attribute "featured_note"
    When a second attribute row with the same record and key is written directly to the database
    Then the write is rejected by a uniqueness constraint

  # The promotion that matters most: postmeta '_thumbnail_id' becomes a foreign key.
  @parity @invariant @critical
  Scenario: The featured asset is a foreign key, not a key-value pair
    Given a record whose featured asset is a stored asset
    When that asset is deleted
    Then the record's featured asset reference is cleared
    And no dangling reference remains

  @parity @invariant
  Scenario: Deleting a record removes its attributes
    Given a record carrying three arbitrary attributes
    When the record is deleted
    Then no attribute rows reference that record

  # TD-07 / F-DD-02: meta_value is unindexed in ALL SIX legacy meta tables, making
  # meta_query the dominant slow-query source. The target indexes it.
  @parity
  Scenario: Attributes are queryable by value
    Given several records carrying an attribute with distinct values
    When records are filtered by that attribute's value
    Then only the matching records are returned

  # BR-META-04. Protected keys carry a leading underscore in the legacy.
  @parity
  Scenario: A protected attribute key is not exposed through the public API
    Given a record carrying a protected attribute
    When the record is fetched through the public API
    Then the protected attribute is absent from the response

  # RISK-008 / implication 6. The slashing convention VANISHES, so every rule that
  # assumed slashed input must be re-read. This scenario is the corpus-level trap
  # that catches a mis-read one.
  @parity @critical
  Scenario Outline: Attribute values round-trip byte-identically
    Given an attribute value of "<value>"
    When the value is stored and read back
    Then the value is byte-identical to what was stored

    Examples:
      | value                      |
      | O'Brien                    |
      | back\slash                 |
      | "quoted"                   |
      | emoji 😀 and 4-byte text   |
