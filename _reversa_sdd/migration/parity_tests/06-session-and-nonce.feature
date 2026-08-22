# language: en
# spec-id: PT-006
# traceability:
#   process_flows: _reversa_sdd/flowcharts/authentication-and-sessions.md
#   target_architecture: BC-05 Identity (AGG-User)
#   target_paradigm: classic OO / Active Record
#   rules: BR-MIGRATE-111..126
#
# BR-AUTH-15 is a SINGLE INVARIANT SPANNING TWO LEGACY MODULES, which is exactly
# why target_architecture.md merges users-roles-capabilities with
# authentication-and-sessions into one context: they fail together.

Feature: Sessions and request tokens
  As the system
  I want session destruction to invalidate every token issued under it
  So that logging out actually revokes authority

  @parity @critical
  Scenario: A valid credential establishes a session
    Given a user with a valid credential
    When the user authenticates
    Then a session exists for that user
    And the session has an expiry instant

  # BR-AUTH-15 + spec-impact-matrix section 6: this coupling is INVISIBLE from
  # either legacy module alone.
  @parity @critical @invariant
  Scenario: Destroying a session invalidates every outstanding token issued under it
    Given an authenticated user with an outstanding request token
    When the user's session is destroyed
    Then the outstanding token is rejected
    And no action authorised by that token succeeds

  @parity @critical
  Scenario: Destroying all sessions invalidates tokens across every device
    Given a user with two active sessions on different devices
    And an outstanding request token issued under each
    When all sessions for that user are destroyed
    Then both tokens are rejected

  @parity
  Scenario: An expired session is not accepted
    Given a session whose expiry instant has passed
    When a request presents that session
    Then the request is treated as unauthenticated

  # Sessions are ROWS now, not a serialized array in usermeta['session_tokens'].
  @parity @invariant
  Scenario: Deleting a user removes their sessions and credentials
    Given a user with an active session and an application password
    When the user is deleted
    Then no session rows reference that user
    And no application password rows reference that user

  # T-10 in data_migration_plan.md. Seed at least one user of each digest format.
  @parity
  Scenario Outline: Legacy password digests remain verifiable and are upgraded on use
    Given a user whose stored digest is in "<format>" format
    When the user authenticates with the correct credential
    Then authentication succeeds
    And the stored digest is rehashed to the target algorithm

    Examples:
      | format |
      | phpass |
      | bcrypt |

  @parity @invariant
  Scenario: A malformed digest never verifies
    Given a user whose stored digest is empty or malformed
    When any credential is presented
    Then authentication fails
