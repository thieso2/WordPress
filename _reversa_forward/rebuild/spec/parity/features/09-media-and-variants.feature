# language: en
# spec-id: PT-009
# traceability:
#   process_flows: _reversa_sdd/code-analysis.md (media-and-attachments)
#   target_architecture: BC-04 Library (AGG-Asset)
#   target_paradigm: classic OO / Active Record
#   rules: BR-MIGRATE-079..088
#
# AD-02: assets are SPLIT OUT of wp_posts. An asset has no body, no excerpt, no
# comment status and no publication workflow — it has a MIME type, a path and
# generated variants. Four legacy postmeta keys existed precisely because the
# post shape did not fit it.

Feature: Assets and their derivatives
  As an editor
  I want uploaded assets to carry their own attributes and variants
  So that media is not modelled as content that happens to be a file

  @parity @critical
  Scenario: Uploading an image generates the registered variants
    Given the registered image sizes are thumbnail, medium and large
    When an editor uploads an image larger than every registered size
    Then a variant exists for each registered size
    And each variant records its own width, height and MIME type

  @parity
  Scenario: An image smaller than a registered size does not gain that variant
    Given the registered size "large" is 1024 pixels wide
    When an editor uploads an image 500 pixels wide
    Then no "large" variant is generated

  @parity @invariant
  Scenario: A duplicate variant name for the same asset is rejected
    Given an asset with a "thumbnail" variant
    When a second "thumbnail" variant for that asset is written directly to the database
    Then the write is rejected by a uniqueness constraint

  # BR-MIGRATE-033: attachment slugs are unique across ALL types in the legacy.
  @parity @invariant
  Scenario: Asset slugs are globally unique
    Given an asset with slug "photo"
    When a second asset with slug "photo" is written directly to the database
    Then the write is rejected by a uniqueness constraint

  # Was postmeta '_wp_attachment_image_alt' — now an attribute of the ASSET,
  # not of the record that displays it.
  @parity
  Scenario: Alt text belongs to the asset
    Given an asset with alt text
    When the asset is displayed within two different records
    Then both display the same alt text

  @parity @invariant
  Scenario: MIME type is determined from content, not from the filename
    Given a file whose extension does not match its content
    When the file is uploaded
    Then the recorded MIME type reflects the content

  @parity @invariant
  Scenario: Deleting an asset removes its variants
    Given an asset with three variants
    When the asset is deleted
    Then no variant rows reference that asset

  @parity
  Scenario: Detaching an asset does not delete it
    Given an asset attached to a published record
    When the record is deleted
    Then the asset still exists
    And the asset is no longer attached to any record
