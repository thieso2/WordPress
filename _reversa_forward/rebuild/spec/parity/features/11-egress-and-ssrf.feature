# language: en
# spec-id: PT-011
# traceability:
#   process_flows: _reversa_sdd/flowcharts/http-api.md
#   target_architecture: BC-14 Egress
#   target_paradigm: classic OO / Active Record
#   rules: BR-MIGRATE-245..257; deviation BR-HTTP-01; contingent BR-FS-07/09/10, BR-UPD-04
#
# BC-14 exists as its own context specifically to make deviation BR-HTTP-01
# STRUCTURAL. In the legacy, SSRF validation is opt-in BY FUNCTION NAME:
# wp_safe_remote_get() validates, wp_remote_get() does not (F-HTTP-05).
# Here there is one door, it validates, and the unsafe path is explicitly named.

Feature: Outbound requests
  As the system
  I want every outbound request validated by default
  So that reaching an internal address requires a deliberate act

  # DEVIATION BR-HTTP-01, approved.
  @parity @deviation @critical
  Scenario: The default client validates the target address
    Given a URL resolving to a private network address
    When the default outbound client requests it
    Then the request is refused before any connection is made

  @parity @deviation @critical
  Scenario: The unsafe client is explicitly named and still auditable
    Given a URL resolving to a private network address
    When the explicitly-unsafe client requests it
    Then the request proceeds
    And the use of the unsafe path is recorded

  @parity @invariant @critical
  Scenario: There is exactly one validating door
    Given the application's outbound request surface
    Then every outbound path routes through the egress client
    And no code path issues an unvalidated request without naming the unsafe client

  @parity
  Scenario Outline: Disallowed schemes are refused
    Given a URL using the "<scheme>" scheme
    When the default outbound client requests it
    Then the request is refused

    Examples:
      | scheme |
      | file   |
      | ftp    |
      | gopher |

  @parity
  Scenario: Redirects are re-validated at each hop
    Given a permitted URL that redirects to a private network address
    When the default outbound client follows the redirect
    Then the redirect target is refused

  # CONTINGENT rules BR-FS-07, BR-FS-09, BR-FS-10, BR-UPD-04. These survive ONLY
  # because DEV-011 kept console.theme-install. If remote theme installation is
  # ever dropped, all four become void together. See parity_specs.md, P-4.
  @parity @critical
  Scenario: A downloaded package is signature-verified before extraction
    Given a theme package downloaded from a remote directory
    When the package is processed
    Then its signature is verified against the trusted keys
    And verification happens before any file is extracted

  @parity @critical
  Scenario: A package failing signature verification is not installed
    Given a downloaded package whose signature does not verify
    When the package is processed
    Then no file is extracted
    And the failure is reported

  # BR-FS-09: signatures of the wrong decoded length are skipped and counted.
  @parity
  Scenario: A malformed signature is skipped rather than treated as valid
    Given a package carrying a signature of incorrect length
    When verification runs
    Then that signature is skipped and counted
    And the package is not treated as verified
