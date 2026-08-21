# User Stories — Administration and recovery

> Derived from `admin-application`, `updates-and-upgrader`, `error-handling-and-recovery-mode`,
> `filesystem-api`, `site-health`.
> Confidence: 🟢 CONFIRMED · 🟡 INFERRED

---

## US-ADM-01 — Reaching the admin

```gherkin
Given I am not logged in
When I request any wp-admin screen
Then auth_redirect() sends me to wp-login.php                         # BR-ADM-02
And the redirect target is validated by wp_validate_redirect()

Given I am logged in without the screen's capability
When I load the screen
Then the screen's own current_user_can() check denies me
And there is NO central policy point that guarantees this check exists # F-ADM-02 ⚠️
```

---

## US-ADM-02 — A plugin update breaks the site

```gherkin
Given a plugin update introduces a fatal error
When the next request loads that plugin
Then WP_Fatal_Error_Handler catches it via register_shutdown_function  # BR-ERR-02
And the offending extension is identified from the error's file path   # BR-ERR-06
And it is recorded in paused-extensions storage
And an email with a signed recovery link is sent, once per day at most # BR-ERR-07

When the NEXT request arrives
Then the paused plugin is SKIPPED at boot                              # BR-BOOT-05
And the site loads normally without it                                 # F-ERR-01

Given the error came from core but was CAUSED by the plugin's data
When attribution runs
Then the WRONG extension may be paused                                 # F-ERR-03 ⚠️
```

---

## US-ADM-03 — Recovering access

```gherkin
Given I received the recovery email
When I follow the link
Then a RECOVERY_MODE_COOKIE is set — httponly, secure on SSL           # BR-ERR-09
And I can reach the admin with the paused extension still disabled

Given a filter set the link TTL shorter than the email rate limit
When the TTL is computed
Then max(ttl, rate_limit) is used instead                              # BR-ERR-08
So that I can never be locked out with an expired link and no replacement
```

🟢 A deliberate guard against misconfiguration of the extension API itself (F-ERR-02).

---

## US-ADM-04 — Updating core

```gherkin
Given an update is available
When I run the update
Then the package is downloaded to a temp file
And its Ed25519 signature is verified against wp_trusted_keys()        # BR-FS-10
And the site enters maintenance mode for the duration                  # BR-UPD-05
And files that no longer exist in the new version are removed          # BR-UPD-06

Given the host has no sodium extension and no sha384
When verification is attempted
Then the result is 'unsupported', NOT 'invalid'                        # BR-FS-07
And the update PROCEEDS UNVERIFIED                                     # F-FS-02 ⚠️

Given the update crashes mid-install
When the next request arrives more than 10 minutes later
Then the stale .maintenance file is IGNORED and the site loads         # BR-BOOT-02
```

---

## US-ADM-05 — Writing files on shared hosting

```gherkin
Given WordPress needs to write to wp-content
When it probes the filesystem
Then it writes a temp file and compares its owner to WordPress's own files  # BR-FS-02
And uses 'direct' only when the owners MATCH
And falls back to ssh2, then ftpext, then ftpsockets                       # BR-FS-05

Given writing succeeds but the owners differ
When the method is chosen
Then 'direct' is REFUSED anyway
```

🟢 "Can write" and "should write" are treated as different questions (F-FS-01).

---

## US-ADM-06 — Diagnosing a broken site

```gherkin
Given scheduled posts are not publishing
When I open Tools → Site Health
Then the loopback test reports whether wp-cron.php can be reached      # BR-SH-04
And slow tests run asynchronously so the page still loads              # BR-SH-01
And each result is good, recommended or critical                       # BR-SH-02
```

🟢 Site Health is the only place core checks its own operating assumptions (F-SH-01).
