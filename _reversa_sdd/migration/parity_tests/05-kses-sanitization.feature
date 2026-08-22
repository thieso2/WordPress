# language: en
# spec-id: PT-005
# traceability:
#   process_flows: _reversa_sdd/code-analysis.md (kses-security)
#   target_architecture: packs/sanitizing (zero declared dependencies)
#   target_paradigm: classic OO / Active Record — a leaf library
#   rules: BR-MIGRATE-292..307; overrides BR-KSES-01/04/05/06/07, BR-FMT-04
#
# ############################################################################
# This is the ONLY flow requiring DIFFERENTIAL testing rather than comparative.
#
# Owner override 2 reproduces the KSES regex implementation VERBATIM, against
# question Q5. Finding F-KSES-05 is knowingly carried forward: the security-
# critical HTML allowlist parses HTML with regular expressions in the new system.
#
# RISK-005 is created BY the migration and did not exist while the rules stayed
# in PHP: PCRE and Ruby's Onigmo differ on anchors, possessive quantifiers,
# backtracking limits and Unicode handling. A pattern that is a correct allowlist
# under PCRE can ADMIT INPUT under Onigmo.
# ############################################################################

Feature: Sanitizing untrusted HTML
  As the system
  I want the allowlist to behave identically to the legacy implementation
  So that two decades of accumulated bypass defences survive the port

  @parity @critical
  Scenario: A disallowed element is stripped
    Given untrusted content containing a script element
    When the content is sanitized
    Then the script element is absent from the output

  @parity @critical
  Scenario: An allowed element with a disallowed attribute keeps the element
    Given untrusted content containing a link with an event-handler attribute
    When the content is sanitized
    Then the link element remains
    And the event-handler attribute is absent

  # OVERRIDE — BR-KSES-04. These four steps encode two decades of bypass attempts
  # and are the highest-value case in this file.
  @parity @override @critical
  Scenario: Scheme normalisation applies all four steps in order
    Given a URL attribute whose scheme is obfuscated with entities, whitespace and null bytes
    When the attribute is normalized
    Then entities are decoded, whitespace stripped, null bytes removed and the result lowercased
    And the normalisation order matches the legacy implementation exactly

  # OVERRIDE — BR-KSES-05.
  @parity @override @critical
  Scenario Outline: The colon is recognised in every encoded form
    Given a URL attribute using "<encoding>" as its scheme separator
    When the attribute is sanitized
    Then the scheme is recognised and evaluated against the allowlist

    Examples:
      | encoding |
      | :        |
      | &#58;    |
      | &#x3a;   |
      | &colon;  |

  # OVERRIDE — BR-KSES-06.
  @parity @override
  Scenario: A truncated colon entity is repaired before splitting
    Given a URL attribute containing a truncated colon entity
    When the attribute is sanitized
    Then the entity is repaired before the scheme is split from the remainder

  # OVERRIDE — BR-KSES-07.
  @parity @override
  Scenario: A feed-prefixed URL is re-examined recursively to a depth of two
    Given a URL attribute with a feed scheme wrapping another scheme
    When the attribute is sanitized
    Then the inner scheme is evaluated against the allowlist
    And recursion stops at two levels

  # RISK-005's actual mitigation. This scenario is the reason the sanitizing pack
  # has zero declared dependencies: it must be runnable against both engines.
  @parity @critical @differential
  Scenario: Every ported pattern is byte-identical to the PHP original
    Given the XSS bypass corpus
    And the legacy PHP implementation available as an oracle
    When each corpus entry is sanitized by both implementations
    Then the outputs are byte-identical for every entry
    And no pattern has been rewritten for idiom

  # The one guarantee the target adds that the legacy could not: architecture.md
  # section 4 records output escaping as "convention only, no type system" (F-FMT-02).
  @parity @invariant
  Scenario: Sanitized markup is a distinct type
    Given a value that has not passed through the sanitizing pack
    When code attempts to render it as trusted markup
    Then the type system rejects the value
