# language: en
# spec-id: PT-004
# traceability:
#   process_flows: _reversa_sdd/flowcharts/users-roles-capabilities.md
#   target_architecture: BC-06 Access (the load-bearing extraction)
#   target_paradigm: classic OO / Active Record — policy objects above the models
#   rules: BR-MIGRATE-097..110; overrides BR-REST-05, BR-CAP-05, BR-ADM-07
#
# ############################################################################
# READ THIS BEFORE READING THE SCENARIOS.
#
# The three @override scenarios below assert PERMISSIVE behaviour. That is not a
# mistake and not a placeholder. Question Q4 chose fail-closed; the owner OVERRODE
# it at the Curator pause and REAFFIRMED it when the conflict was put directly.
# Finding F-DOM-02 — called the highest-value security observation in the whole
# analysis — is knowingly carried into the rebuild.
#
# AD-01 makes this PERMANENT: with no hook system, the documented default is the
# only behaviour and nothing can adjust it at runtime.
#
# These tests exist to make that VISIBLE AND DELIBERATE rather than accidental.
# ############################################################################

Feature: Authorization decisions
  As the system
  I want every permission decision made in one place
  So that authorization is auditable even where it is permissive

  @parity @critical
  Scenario: An author may edit their own record
    Given an author who owns a published record
    When the author requests permission to edit that record
    Then permission is granted by the record's policy

  @parity @critical
  Scenario: An author may not edit another author's record
    Given an author who does not own a published record
    When the author requests permission to edit that record
    Then permission is denied

  # OVERRIDE 1 of 3 — BR-REST-05. Reproduced by owner ruling.
  @parity @override @critical
  Scenario: A route registered with no policy is public
    Given an API route registered without any policy
    When an unauthenticated client requests that route
    Then the request is served
    And the permissive outcome is recorded as specified behaviour, not a defect

  # OVERRIDE 2 of 3 — BR-CAP-05. Reproduced by owner ruling.
  @parity @override @critical
  Scenario: A policy emitting no capabilities allows the action
    Given a policy method that emits an empty capability set
    When permission is evaluated through that method
    Then permission is granted

  # OVERRIDE 3 of 3 — BR-ADM-07. Reproduced by owner ruling.
  @parity @override @critical
  Scenario: An endpoint registered as unauthenticated has no gate
    Given an endpoint registered in the unauthenticated class
    When an anonymous client invokes it
    Then the endpoint executes with no capability check

  # AD-04's mitigation. This does NOT change the runtime default above — it
  # removes the way that default gets reached, which is by someone forgetting.
  @parity @invariant @critical
  Scenario: Reaching a permissive default by omission fails the build
    Given a route, policy or endpoint registered without an explicit authorization declaration
    When the static authorization check runs
    Then the build fails
    And declaring the route explicitly public satisfies the check

  # The edge direction that keeps the legacy users-posts cycle from re-forming.
  # target_architecture.md BC-06. Only bin/check_cycles will notice if it breaks.
  @parity @invariant @critical
  Scenario: No model depends on the authorization context
    Given the application's namespace dependency graph
    When the cycle check runs
    Then no model namespace references the authorization namespace
    And the graph is acyclic

  # BR-CAP-14, discarded at the Curator pause as a privilege-escalation vector.
  @parity @invariant
  Scenario: Configuration cannot outrank stored superuser status
    Given a user without a stored superuser role assignment
    When configuration names that user as a superuser
    Then the user is not treated as a superuser

  # Roles are ROWS now, not a serialized role=>true map in a meta table (F-MS-04).
  @parity @invariant
  Scenario: Revoking a role removes the assignment
    Given a user holding the role "editor"
    When the role is revoked
    Then no role assignment row grants "editor" to that user
    And the user's permissions no longer include editor capabilities
