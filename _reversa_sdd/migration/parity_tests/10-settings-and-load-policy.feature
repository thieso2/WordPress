# language: en
# spec-id: PT-010
# traceability:
#   process_flows: _reversa_sdd/flowcharts/options-and-transients.md
#   target_architecture: BC-07 Configuration (AGG-Setting) + AD-06
#   target_paradigm: classic OO / Active Record
#   rules: BR-MIGRATE-008..014
#
# AD-06: THREE OF FOUR responsibilities leave. F-DD-03 records that the legacy
# options table holds site config PLUS the entire compiled routing table PLUS the
# entire cron queue PLUS the transient cache, behind one unique index — making it
# the most contended table in WordPress.

Feature: Settings and their load policy
  As the system
  I want settings to hold settings only
  So that a size heuristic can never de-autoload the router

  @parity @critical
  Scenario: Setting and reading a value
    Given no setting named "site_title"
    When the value "Example" is stored under "site_title"
    Then reading "site_title" returns "Example"

  @parity @invariant
  Scenario: Setting names are unique
    Given a setting named "site_title"
    When a second row with the same name is written directly to the database
    Then the write is rejected by a uniqueness constraint

  # DEVIATION BR-OPT-04, approved. In the legacy update_option() returns false for
  # UNCHANGED, which is indistinguishable from failure.
  @parity @deviation @critical
  Scenario: An unchanged write is distinguishable from a failed write
    Given a setting whose value is "Example"
    When the same value "Example" is written again
    Then the operation reports success with no change
    And this is distinguishable from a write that failed

  # BR-OPT-12.
  @parity
  Scenario: The home URL falls back to the site URL when empty
    Given the site URL is set and the home URL is empty
    When the home URL is read
    Then it returns the site URL

  # BR-OPT-06 / F-RW-02 / F-CRON-03. The failure mode this whole context redesign
  # exists to delete: a 150 KB threshold silently de-autoloading the routing table
  # or the cron queue.
  @parity @invariant @critical
  Scenario: Load policy is explicit and never derived from value size
    Given a setting marked to load eagerly
    When its value grows beyond any historical size threshold
    Then it still loads eagerly
    And no size heuristic changes its load policy

  # AD-06, asserted structurally.
  @parity @invariant @critical
  Scenario: The settings store cannot hold derived or queued state
    Given the settings store
    Then no setting holds a compiled routing table
    And no setting holds a scheduled-work queue
    And no setting holds a cached value with an expiry

  # BR-OPT-08: transients shared the options table under _transient_* prefixes.
  @parity
  Scenario: Cached values with expiry live in the cache, not in settings
    Given a value cached with a 60 second expiry
    When the value is stored
    Then it is not present in the settings store
    And it is retrievable from the cache before expiry

  # BR-OPT-02: the legacy transparently remaps deprecated option aliases.
  @parity
  Scenario: A deprecated setting alias resolves to its current name
    Given a setting stored under its current name
    When it is read through its deprecated alias
    Then the current value is returned
