# ADR-006 — Cron without a daemon

**Status:** Accepted · **Date:** ~2006 · **Confidence:** 🟢 CONFIRMED

## Context

WordPress needed scheduled work — publishing future-dated posts, checking for updates, cleaning
transients — but its target hosting had no shell access, no crontab and no long-running processes.

## Decision

Store the schedule in an option and drain it by **piggybacking on incoming HTTP requests**. When a
request arrives and work is due, fire a non-blocking loopback request to `wp-cron.php`.

## Evidence

- `wp-includes/cron.php`, ~1,400 lines; the queue is the `cron` option (BR-CRON-01).
- `spawn_cron()` (`cron.php:899`) sets a `doing_cron` transient as a lock, then issues a
  non-blocking request to `site_url('wp-cron.php')`.
- `WP_CRON_LOCK_TIMEOUT` (60 s) doubles as a rate limit (BR-CRON-08).
- `ALTERNATE_WP_CRON` redirects the **visitor's browser** back to the same URL with a marker for
  hosts where loopback fails (BR-CRON-10).
- Site Health's loopback test exists specifically to detect that this mechanism is broken
  (BR-SH-04).

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| Require a system crontab | Unavailable on the shared hosting that was WordPress's entire market. |
| A long-running PHP worker | Impossible in the target environment. |
| Fire scheduled work synchronously in the request | Would make an arbitrary visitor wait for a plugin's slow job. |

## Consequences

**Positive**
- Scheduled work exists at all on hosting that offers no scheduler.
- Zero configuration for the common case.
- `DISABLE_WP_CRON` + a real crontab is available for sites that can use it — the standard
  production configuration.

**Negative**
- **A site with no traffic runs no scheduled work.** Scheduled posts do not publish; transients are
  never swept; updates are never checked (F-CRON-01).
- The lock is a transient, so its cross-process correctness depends on whether a persistent object
  cache exists. Without one it is a DB row with no atomic compare-and-set, and two concurrent
  requests can both acquire it (F-CRON-02).
- The entire schedule sits in one autoloaded option, loaded on every request (F-CRON-03).
- `ALTERNATE_WP_CRON` makes a visitor's browser the scheduler and adds a redirect to their request
  (F-CRON-05).
