# ADR-010 — Move to bcrypt with HMAC-SHA-384 pre-hashing

**Status:** Accepted · **Date:** 2025 (WordPress 6.8) · **Confidence:** 🟢 CONFIRMED

## Context

WordPress had used **phpass** (portable MD5-based hashing, `$P$` prefix) since 2008, chosen because
PHP 4 lacked anything better. By 2025 `password_hash()` was universal, and phpass was
computationally weak by modern standards. But bcrypt truncates input at **72 bytes**, silently
discarding entropy from longer passphrases.

## Decision

Switch to bcrypt, and **pre-hash the password with HMAC-SHA-384** before passing it to
`password_hash()` so long passphrases retain their entropy. Prefix the result `$wp` to distinguish
it from vanilla bcrypt. Keep verifying old phpass hashes indefinitely.

## Evidence

- `05770e25c3 Security: Switch to using bcrypt for hashing user passwords and BLAKE2b for hashing
  application passwords and security keys` (2025-02-17).
- `d75f025337 Security: Reintroduce support for passwords hashed with MD5` (2025-02-28) — a
  *reintroduction* two weeks later; even MD5 hashes from ancient installs must still verify
  (ADR-002).
- `746ed91e1e Application Passwords: Correct the fallback behaviour…` (2025-04-03).
- The implementation (`pluggable.php:2771`):

```php
$password_to_hash = base64_encode( hash_hmac( 'sha384', trim($password), 'wp-sha384', true ) );
return '$wp' . password_hash( $password_to_hash, PASSWORD_BCRYPT, $options );
```

- Three hash formats now coexist: `$P$` (phpass), `$2y$` (vanilla bcrypt), `$wp$2y$` (pre-hashed).
- `strlen($password) > 4096 → return '*'` — a DoS guard expressed as a permanently-failing hash
  (BR-AUTH-02).

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| Plain bcrypt without pre-hashing | Silently truncates at 72 bytes; a 200-character passphrase would be no stronger than its first 72 bytes. |
| Argon2id | Requires `PASSWORD_ARGON2ID`, unavailable on many hosts. The commit `0caf2af8ea Don't fail the Argon2-related tests when it's not available` shows it was evaluated and made optional, not default. |
| SHA-512 pre-hash | Would work, but SHA-384 avoids the length-extension property and produces a shorter base64 string. |
| Force a password reset for all users | Unacceptable: ADR-002, and it would lock out sites whose owners no longer have working email. |

## Consequences

**Positive**
- Password strength no longer caps at 72 bytes.
- The `wp-sha384` HMAC key provides domain separation; base64 encoding avoids null bytes in the
  bcrypt input. Both details are correct (F-AUTH-07).
- Old hashes keep verifying; rehashing happens transparently on next login via
  `wp_password_needs_rehash()`.

**Negative**
- Three hash formats in one column, discriminated by prefix, permanently.
- `wp_generate_auth_cookie()` must branch on hash prefix to extract the password fragment —
  `substr($hash, 8, 4)` for `$P$`/`$2y$`, `substr($hash, -4)` otherwise (BR-AUTH-06).
- MD5 support was reintroduced *after* the switch, so the weakest historical format is still
  accepted for verification.
