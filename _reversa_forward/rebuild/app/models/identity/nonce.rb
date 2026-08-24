# frozen_string_literal: true

module Identity
  # Request tokens — the legacy's nonces (BR-MIGRATE-122..126, BR-AUTH-12..16).
  #
  # Lives in Identity, not in Access, and that placement is the whole point of BC-05.
  # A nonce is not an authorization decision ("may this actor do this?"); it is a
  # statement about WHICH SESSION a request came from. target_architecture.md merges
  # users-roles-capabilities with authentication-and-sessions precisely because
  # BR-AUTH-15 — destroying a session invalidates every outstanding nonce issued under
  # it — is one invariant spanning both legacy modules. Splitting them would put the two
  # halves of a single invariant in two contexts.
  #
  # ── Why this is derived state and not a table ────────────────────────────────
  # AD-05 turns compensating check-then-act loops into database constraints. A nonce is
  # not one of those: wp_create_nonce() stores nothing, and neither does this. The token
  # IS an HMAC over (tick, action, user, session token), so it carries its own validity.
  # Making it a row would add a write to every rendered form and a reaper to every
  # deploy, and would move the BR-AUTH-15 invariant from "cannot be expressed otherwise"
  # to "enforced by a foreign key we remembered to add".
  #
  # ── How BR-AUTH-15 is enforced here ──────────────────────────────────────────
  # `verify` resolves the presented session token through Identity::Session.authenticate,
  # which only ever returns a LIVE session row. A destroyed or expired session resolves
  # to nothing, the actor collapses to the logged-out identity (uid 0, BR-MIGRATE-126),
  # and a nonce minted under uid N cannot match. Session destruction therefore
  # invalidates outstanding nonces as a consequence of the identity lookup, not as a
  # separate cleanup step that could be forgotten. This is the same mechanism the legacy
  # relies on: wp_validate_auth_cookie() fails once the token row is gone, the request
  # becomes uid 0, and every nonce it carries stops verifying.
  #
  # ── AD-01: no hook system ────────────────────────────────────────────────────
  # The legacy exposes three filters on this path — `nonce_life`, `nonce_user_logged_out`
  # and the `wp_verify_nonce_failed` action. All three are resolved to their unfiltered
  # defaults below and there is no way to change them.
  module Nonce
    # BR-MIGRATE-122 / BR-AUTH-12: nonce_life, unfiltered, is DAY_IN_SECONDS. A nonce
    # lives two ticks, so the tick is half the lifetime and both the current and the
    # previous tick are accepted.
    LIFETIME = 24.hours
    TICK = LIFETIME / 2

    # BR-MIGRATE-126 / BR-AUTH-16: every logged-out actor shares uid 0. The legacy lets
    # `nonce_user_logged_out` supply an identity instead; under AD-01 it cannot.
    LOGGED_OUT_UID = 0

    # BR-MIGRATE-124 / BR-AUTH-14: "10 hex characters taken from offset -12 of a wp_hash()
    # result". The offset is an artefact of slicing a 32-character MD5; what is
    # observable — and what the screen-diff harness normalises (target_screens.md) — is a
    # 10-character hex token, so that shape is preserved. The digest underneath is
    # HMAC-SHA-256 rather than HMAC-MD5: wp_hash()'s algorithm is not part of the rule,
    # and MD5 is not available as a MAC in this stack.
    LENGTH = 10

    module_function

    # BR-MIGRATE-122: ceil(now / (lifetime / 2)), matching wp_nonce_tick().
    def tick(now = Time.current)
      (now.to_i / TICK.to_i.to_f).ceil
    end

    # `session_token` is the raw token handed out by Identity::Session.issue!. Passing
    # nil mints an anonymous token under uid 0 (BR-MIGRATE-126).
    def issue(action, session_token: nil)
      session = live_session(session_token)
      digest(tick, action, session&.user_id || LOGGED_OUT_UID, session_token)
    end

    # BR-MIGRATE-123 / BR-AUTH-13: 1 when the token is 0-12 hours old, 2 when it is
    # 12-24 hours old, false otherwise. Never true — the age is load-bearing information
    # (autosave renews a token in its second tick), so the legacy's tri-state return is
    # preserved rather than flattened to a boolean.
    def verify(nonce, action, session_token: nil)
      nonce = nonce.to_s
      return false if nonce.empty?

      # BR-AUTH-15 lands here: no LIVE session, no session-bound identity.
      session = live_session(session_token)
      uid = session&.user_id || LOGGED_OUT_UID

      i = tick
      return 1 if same?(digest(i, action, uid, session_token), nonce)
      return 2 if same?(digest(i - 1, action, uid, session_token), nonce)

      false
    end

    # The scenario's "no action authorised by that token succeeds": the guard, not the
    # caller, decides whether the block runs. Returns nil and yields nothing when the
    # token does not verify.
    def guard(nonce, action, session_token: nil)
      status = verify(nonce, action, session_token: session_token)
      return nil unless status

      yield status
    end

    # ── internals ────────────────────────────────────────────────────────────────

    def live_session(raw)
      raw.presence && Identity::Session.authenticate(raw)
    end

    def digest(tick_value, action, uid, session_token)
      data = [tick_value, action, uid, session_token.to_s].join("|")
      OpenSSL::HMAC.hexdigest("SHA256", salt, data)[-12, LENGTH]
    end

    # wp_salt('nonce'): a per-installation secret scoped to this use. Derived from
    # secret_key_base so it rotates with the application's credentials, exactly as
    # rotating the WordPress NONCE_SALT invalidates every outstanding nonce.
    def salt
      @salt ||= Rails.application.key_generator.generate_key("identity/nonce", 32)
    end

    # BR-MIGRATE-117 / BR-AUTH-07 applies to the whole family: constant-time comparison.
    def same?(expected, presented)
      ActiveSupport::SecurityUtils.secure_compare(expected, presented)
    end
  end
end
