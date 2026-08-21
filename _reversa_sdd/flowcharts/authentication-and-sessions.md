# Flowchart — `authentication-and-sessions`

> 🟢 CONFIRMED — derived from `wp-includes/pluggable.php`

## Password hashing

```mermaid
flowchart TD
    A["wp_hash_password(password)<br/>#[\SensitiveParameter]"] --> B{"global $wp_hasher set?"}
    B -->|yes| C["wp_hasher-&gt;HashPassword(trim(password))<br/>legacy phpass override"]
    B -->|no| D{"strlen(password) &gt; 4096?"}
    D -->|yes| E[["return '*'<br/>an unmatchable hash —<br/>DoS guard, not an error"]]
    D -->|no| F["algorithm = apply_filters(<br/>'wp_hash_password_algorithm',<br/>PASSWORD_BCRYPT)"]

    F --> G{"algorithm === PASSWORD_BCRYPT?"}
    G -->|no| H["password_hash(password,<br/>algorithm, options)"]
    G -->|yes| I["bcrypt truncates at 72 bytes<br/>⇒ PRE-HASH first"]
    I --> J["base64_encode(<br/>hash_hmac('sha384',<br/>trim(password),<br/>'wp-sha384', true) )<br/><br/>• SHA-384 keeps entropy of long passphrases<br/>• 'wp-sha384' key = domain separation<br/>• base64 avoids null bytes"]
    J --> K["'$wp' . password_hash(<br/>password_to_hash, PASSWORD_BCRYPT)"]

    L["Three coexisting formats:<br/>$P$ phpass · $2y$ vanilla bcrypt · $wp$2y$ pre-hashed"]

    style E fill:#c62828,color:#fff
    style K fill:#2e7d32,color:#fff
    style L fill:#1565c0,color:#fff
```

## Auth cookie generation — two-stage HMAC

```mermaid
flowchart TD
    A["wp_generate_auth_cookie(user_id,<br/>expiration, scheme, token)"] --> B{token supplied?}
    B -->|no| C["WP_Session_Tokens::get_instance(user_id)<br/>-&gt;create(expiration)"]
    B -->|yes| D
    C --> D{"user_pass starts with<br/>'$P$' or '$2y$'?"}

    D -->|yes| E["pass_frag = substr(user_pass, 8, 4)<br/>legacy offset"]
    D -->|no| F["pass_frag = substr(user_pass, -4)<br/>tail — avoids long hash prefixes"]

    E --> G
    F --> G["STAGE 1 — key derivation<br/>key = wp_hash(<br/>&nbsp;&nbsp;user_login | pass_frag |<br/>&nbsp;&nbsp;expiration | token,<br/>&nbsp;&nbsp;scheme )<br/><br/>salted with AUTH_KEY / AUTH_SALT"]

    G --> H["STAGE 2 — payload HMAC<br/>hash = hash_hmac('sha256',<br/>&nbsp;&nbsp;user_login | expiration | token,<br/>&nbsp;&nbsp;key )"]

    H --> I["cookie = user_login | expiration |<br/>token | hash"]
    I --> J["apply_filters('auth_cookie', …)"]

    K[["pass_frag is NEVER transmitted.<br/>It only enters key derivation.<br/>⇒ changing the password changes the key<br/>⇒ every outstanding cookie is invalidated"]]

    style G fill:#1565c0,color:#fff
    style K fill:#7b1fa2,color:#fff
    style J fill:#2e7d32,color:#fff
```

## Auth cookie validation

```mermaid
flowchart TD
    A["wp_validate_auth_cookie(cookie, scheme)"] --> B["wp_parse_auth_cookie()<br/>→ username | expiration | token | hmac"]
    B --> C{"wp_doing_ajax() OR<br/>REQUEST_METHOD === 'POST'?"}
    C -->|yes| D["expired = expiration + HOUR_IN_SECONDS<br/><br/>grace period so a long-composed<br/>form submission doesn't fail"]
    C -->|no| E["expired = expiration"]

    D --> F
    E --> F{"expired &lt; time()?"}
    F -->|yes| G[["do_action('auth_cookie_expired')<br/>return false"]]
    F -->|no| H["user = get_user_by('login', username)"]

    H --> I{user found?}
    I -->|no| J[["do_action('auth_cookie_bad_username')<br/>return false"]]
    I -->|yes| K["recompute pass_frag, key and hash<br/>exactly as in generation"]

    K --> L{"hash_equals(hash, hmac)?<br/>CONSTANT TIME"}
    L -->|no| M[["do_action('auth_cookie_bad_hash')<br/>return false"]]
    L -->|yes| N["manager = WP_Session_Tokens::get_instance(user-&gt;ID)"]

    N --> O{"manager-&gt;verify(token)?"}
    O -->|no| P[["do_action('auth_cookie_bad_session_token')<br/>return false"]]
    O -->|yes| Q["do_action('auth_cookie_valid')<br/>return user-&gt;ID"]

    style G fill:#ef6c00,color:#fff
    style J fill:#c62828,color:#fff
    style M fill:#c62828,color:#fff
    style P fill:#c62828,color:#fff
    style Q fill:#2e7d32,color:#fff
    style L fill:#1565c0,color:#fff
```

## Cookie lifetimes

```mermaid
flowchart LR
    subgraph R["Remember me"]
        A["expiration = now + 14 days<br/>(HMAC-bound)"] --> B["expire = expiration + 12 hours<br/>(browser cookie)"]
        B --> C["the browser keeps sending a<br/>just-expired cookie for 12h<br/>⇒ server can redirect to login<br/>rather than treat as anonymous"]
    end

    subgraph N["Normal login"]
        D["expiration = now + 2 days"] --> E["expire = 0<br/>SESSION COOKIE<br/>dies with the browser"]
    end

    subgraph S["Cookie selection"]
        F{"is_ssl()?"} -->|yes| G["SECURE_AUTH_COOKIE<br/>scheme 'secure_auth'"]
        F -->|no| H["AUTH_COOKIE<br/>scheme 'auth'"]
        I["LOGGED_IN_COOKIE always issued.<br/>Secure flag requires secure auth cookie<br/>AND home URL scheme == https —<br/>the front end may be HTTP while<br/>the admin is HTTPS"]
    end

    style C fill:#1565c0,color:#fff
    style I fill:#7b1fa2,color:#fff
```

## Nonces — time-windowed HMACs, not nonces

```mermaid
flowchart TD
    A["wp_nonce_tick(action)"] --> B["nonce_life = apply_filters(<br/>'nonce_life', DAY_IN_SECONDS)"]
    B --> C["tick = ceil( time() / (nonce_life / 2) )<br/>⇒ a new tick every 12 hours"]

    D["wp_verify_nonce(nonce, action)"] --> E["uid = current_user-&gt;ID"]
    E --> F{"uid == 0?"}
    F -->|yes| G["uid = apply_filters(<br/>'nonce_user_logged_out', 0, action)<br/><br/>⚠️ by default ALL logged-out users<br/>share the SAME nonce per action"]
    F -->|no| H
    G --> H["token = wp_get_session_token()"]

    H --> I["i = wp_nonce_tick(action)"]
    I --> J["expected = substr( wp_hash(<br/>i | action | uid | token,<br/>'nonce' ), -12, 10 )<br/><br/>10 hex chars ≈ 40 bits"]
    J --> K{"hash_equals(expected, nonce)?"}
    K -->|yes| L[["return 1<br/>0–12 hours old"]]
    K -->|no| M["expected = substr( wp_hash(<br/>(i-1) | action | uid | token,<br/>'nonce' ), -12, 10 )"]
    M --> N{"hash_equals?"}
    N -->|yes| O[["return 2<br/>12–24 hours old<br/>⚠️ this signal is usually discarded"]]
    N -->|no| P[["do_action('wp_verify_nonce_failed')<br/>return FALSE"]]

    Q[["NEVER returns true.<br/>if ( wp_verify_nonce(...) === true ) ALWAYS FAILS."]]
    R[["Deterministic within the window:<br/>same user + same action + same token<br/>⇒ SAME value for 12 hours.<br/>Defends against CSRF, not replay."]]

    style G fill:#ef6c00,color:#fff
    style L fill:#2e7d32,color:#fff
    style O fill:#ef6c00,color:#fff
    style P fill:#c62828,color:#fff
    style Q fill:#c62828,color:#fff
    style R fill:#7b1fa2,color:#fff
```

## Session tokens tie it together

```mermaid
flowchart TD
    A["login"] --> B["WP_Session_Tokens::create()<br/>stored in wp_usermeta<br/>key 'session_tokens'"]
    B --> C["token embedded in the AUTH COOKIE"]
    B --> D["token embedded in EVERY NONCE"]

    E["destroy_all_sessions()"] --> F["removes all tokens"]
    F --> G["every auth cookie fails<br/>manager-&gt;verify(token)"]
    F --> H["every outstanding nonce<br/>fails hash comparison"]

    I[["'Log out everywhere' invalidates<br/>cookies AND nonces in one step,<br/>because both bind to the token"]]

    style I fill:#1565c0,color:#fff
```
