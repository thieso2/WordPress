# Flowchart — `http-api`

> 🟢 CONFIRMED — derived from `wp-includes/http.php` and `wp-includes/class-wp-http.php`

## Safe vs unsafe — the whole distinction

```mermaid
flowchart LR
    A["wp_remote_get(url)"] --> B["WP_Http::request()<br/>NO URL VALIDATION"]
    C["wp_safe_remote_get(url)"] --> D["wp_http_validate_url(url)"]
    D --> E{valid?}
    E -->|no| F[["WP_Error — request never made"]]
    E -->|yes| B

    G[["A plugin fetching a user-supplied URL with<br/>wp_remote_get() HAS an SSRF vulnerability.<br/>The same call with wp_safe_remote_get() does not.<br/>The API makes the UNSAFE call shorter."]]

    style A fill:#c62828,color:#fff
    style C fill:#2e7d32,color:#fff
    style F fill:#ef6c00,color:#fff
    style G fill:#7b1fa2,color:#fff
```

## `wp_http_validate_url()` — the SSRF guard

```mermaid
flowchart TD
    A["wp_http_validate_url(url)"] --> B{"is_string AND non-empty<br/>AND NOT is_numeric?"}
    B -->|no| R[["return FALSE"]]
    B -->|yes| C["url = wp_kses_bad_protocol(url, ['http','https'])"]

    C --> D{"url falsy OR<br/>strtolower(url) !== strtolower(original)?"}
    D -->|yes| R
    D -->|no| E[["✅ SANITIZE-AS-VALIDATOR:<br/>if cleaning CHANGED the URL at all,<br/>REJECT — never use the cleaned form"]]

    E --> F["parse_url(url)"]
    F --> G{"parse failed OR<br/>host empty?"}
    G -->|yes| R
    G -->|no| H{"user or pass set?<br/>http://user:pass@host/"}
    H -->|yes| R
    H -->|no| I{"strpbrk(host, ':#?[]')?"}
    I -->|yes| S[["return FALSE<br/>⚠️ also excludes ALL<br/>IPv6 literal addresses"]]
    I -->|no| J{"host === home option host?<br/>(case-insensitive)"}

    J -->|"YES — same host"| K[["SKIP all IP checks<br/>needed for loopback cron<br/>and REST self-requests"]]
    J -->|no| L{"host is a dotted quad?"}
    L -->|yes| M["ip = host"]
    L -->|no| N["ip = gethostbyname(host)"]
    N --> O{"ip === host?<br/>resolution failed"}
    O -->|yes| R
    O -->|no| M

    M --> P{"ip in any of the<br/>13 BLOCKED RANGES?"}
    P -->|yes| Q{"apply_filters(<br/>'http_request_host_is_external',<br/>FALSE, host, url)"}
    Q -->|"false (default)"| R
    Q -->|true| T
    P -->|no| T{"explicit port in URL?"}

    K --> T
    T -->|no| U[["return url — VALID"]]
    T -->|yes| V["allowed = apply_filters(<br/>'http_allowed_safe_ports',<br/>[80, 443, 8080], host, url)"]
    V --> W{"port in allowed?"}
    W -->|yes| U
    W -->|no| R

    style R fill:#c62828,color:#fff
    style S fill:#c62828,color:#fff
    style E fill:#1565c0,color:#fff
    style K fill:#ef6c00,color:#fff
    style U fill:#2e7d32,color:#fff
```

## The 13 blocked IPv4 ranges

```mermaid
flowchart TD
    subgraph P["Private / internal"]
        A["10.0.0.0/8"]
        B["172.16.0.0/12"]
        C["192.168.0.0/16"]
        D["100.64.0.0/10 — CGNAT"]
    end
    subgraph L["Local"]
        E["127.0.0.0/8 — loopback"]
        F["0.0.0.0/8 — this network"]
        G["169.254.0.0/16 — link-local<br/>⚠️ AND CLOUD METADATA<br/>169.254.169.254"]
    end
    subgraph R["Reserved / documentation"]
        H["192.0.0.0/24 — IETF"]
        I["192.0.2.0/24 — TEST-NET-1"]
        J["198.51.100.0/24 — TEST-NET-2"]
        K["203.0.113.0/24 — TEST-NET-3"]
        M["192.88.99.0/24 — 6to4 relay"]
        N["198.18.0.0/15 — benchmarking"]
    end
    subgraph S["Special"]
        O["224.0.0.0/4 — multicast"]
        Q["240.0.0.0/4 — reserved<br/>incl. 255.255.255.255"]
    end

    T[["The inline comment on 169.254.0.0/16<br/>names cloud metadata explicitly —<br/>a deliberate defense against the<br/>AWS/GCP credential-theft attack."]]

    style G fill:#c62828,color:#fff
    style T fill:#7b1fa2,color:#fff
```

## Residual gaps in the guard

```mermaid
flowchart TD
    A["The check resolves the hostname to an IP<br/>and validates THAT."] --> B["The request is then made<br/>BY HOSTNAME."]
    B --> C[["⚠️ DNS REBINDING:<br/>a DNS entry that resolves differently<br/>between check and request defeats the guard.<br/>Nothing pins the resolved address."]]

    D["gethostbyname() returns IPv4 only."] --> E[["⚠️ A hostname resolving to an IPv6<br/>address is never range-checked.<br/>IPv6 literals are rejected, but<br/>IPv6-resolving names are not."]]

    F["Same-host exemption skips all IP checks."] --> G[["⚠️ A site whose 'home' option points at<br/>an internal hostname can be used<br/>to reach that host."]]

    style C fill:#ef6c00,color:#fff
    style E fill:#ef6c00,color:#fff
    style G fill:#ef6c00,color:#fff
```
