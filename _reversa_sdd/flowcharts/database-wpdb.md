# Flowchart — `database-wpdb`

> 🟢 CONFIRMED — derived from `wp-includes/class-wpdb.php`

## `wpdb::prepare()` — the SQL-injection boundary

```mermaid
flowchart TD
    A["prepare(query, ...args)"] --> B{query is null?}
    B -->|yes| C[return null]
    B -->|no| D{"query contains '%'?"}
    D -->|no| E[early return]
    D -->|yes| F["strip caller quotes:<br/>'%s' → %s, \"%s\" → %s"]

    F --> G["escape unrecognized percents<br/>preg_replace → %%"]
    G --> H["preg_split on placeholder pattern<br/>PREG_SPLIT_DELIM_CAPTURE<br/>stride = 3"]
    H --> I["placeholder_count = (count - 1) / 3"]
    I --> J{"args passed as<br/>single array?"}
    J -->|yes| K[flatten args]
    J -->|no| L
    K --> L[walk placeholders, stride 3]

    L --> M{placeholder type}
    M -->|"%f"| N["rewrite to %F<br/>locale-unaware float"]
    M -->|"%i"| O["rewrite to backtick-%s-backtick<br/>record index in arg_identifiers"]
    M -->|"%s"| P[record index in arg_strings]
    M -->|"%d / %F"| Q[numeric — no quoting]

    N --> R
    O --> R
    P --> R
    Q --> R{"array_intersect(<br/>arg_identifiers, arg_strings)<br/>non-empty?"}

    R -->|yes| S[["re-parse to build conflict list<br/>_doing_it_wrong()<br/>RETURN NULL"]]
    R -->|no| T{"count(args) ==<br/>placeholder_count?"}

    T -->|no| U["_doing_it_wrong()"]
    U --> V{too few args AND<br/>no numbered placeholders?}
    V -->|yes| W[["return '' — empty query<br/>query() will refuse it"]]
    V -->|no| X
    T -->|yes| X[escape values<br/>+ placeholder_escape sentinel]
    X --> Y[interpolate]
    Y --> Z[return prepared SQL]

    style C fill:#616161,color:#fff
    style S fill:#c62828,color:#fff
    style W fill:#ef6c00,color:#fff
    style Z fill:#2e7d32,color:#fff
```

## Placeholder-escape sentinel — second-order injection defense

```mermaid
sequenceDiagram
    participant C as Caller
    participant P as prepare()
    participant F as 'query' filter (prio 0)
    participant M as MySQL

    C->>P: prepare("… WHERE x = %s", "50%s off")
    Note over P: value contains a literal %s
    P->>P: placeholder_escape() → {hmac_sha256(...)}
    P->>P: replace every literal % with the sentinel
    P-->>C: SQL containing the sentinel, not %
    Note over C: a later prepare() cannot<br/>re-interpret the value as a placeholder
    C->>M: $wpdb->query(sql)
    M-->>F: apply_filters('query', sql)
    F->>F: remove_placeholder_escape()<br/>sentinel → %
    F-->>M: real SQL executed
```

## `wpdb::query()` — execution gate

```mermaid
flowchart TD
    A["query(sql)"] --> B{ready?}
    B -->|no| C["check_current_query = true<br/>return false"]
    B -->|yes| D["sql = apply_filters('query', sql)"]
    D --> E{sql falsy?}
    E -->|yes| F[insert_id = 0<br/>return false]
    E -->|no| G["flush()"]

    G --> H{"check_current_query<br/>AND NOT check_ascii(sql)?"}
    H -->|yes| I["strip_invalid_text_from_query(sql)"]
    I --> J{stripped !== original?}
    J -->|yes| K[["last_error = 'contains invalid data'<br/>QUERY REFUSED<br/>return false"]]
    J -->|no| L
    H -->|no| L["last_query = sql<br/>_do_query(sql)"]

    L --> M{"dbh empty OR<br/>mysqli_errno == 2006<br/>(server gone away)"}
    M -->|yes| N{"check_connection()"}
    N -->|reconnected| O["_do_query(sql)<br/>retried ONCE"]
    N -->|failed| P[insert_id = 0<br/>return false]
    M -->|no| Q
    O --> Q["last_error = mysqli_error(dbh)"]

    Q --> R{last_error set?}
    R -->|yes| S{insert_id set AND<br/>sql is INSERT/REPLACE?}
    S -->|yes| T[insert_id = 0]
    S -->|no| U
    T --> U["print_error()<br/>return false"]
    R -->|no| V{"sql is CREATE / ALTER /<br/>TRUNCATE / DROP?"}
    V -->|yes| W[return raw result]
    V -->|no| X[return rows_affected<br/>or cache rows in last_result]

    style K fill:#c62828,color:#fff
    style U fill:#c62828,color:#fff
    style W fill:#2e7d32,color:#fff
    style X fill:#2e7d32,color:#fff
```

## Connection lifecycle and reconnect

```mermaid
flowchart TD
    A["db_connect()"] --> B["parse_db_host()"]
    B --> C[mysqli connect]
    C --> D{connected?}
    D -->|no| E[["bail() — HTML error page"]]
    D -->|yes| F["init_charset() → determine_charset()"]
    F --> G["set_charset(): SET NAMES + COLLATE"]
    G --> H["set_sql_mode()<br/>REMOVE: NO_ZERO_DATE, ONLY_FULL_GROUP_BY,<br/>STRICT_TRANS_TABLES, STRICT_ALL_TABLES,<br/>TRADITIONAL, ANSI"]
    H --> I["select(dbname)"]
    I --> J[ready = true]

    K["check_connection()"] --> L{"mysqli_query(dbh, 'DO 1')<br/>succeeds?"}
    L -->|yes| M[alive — return true]
    L -->|no| N[suppress E_WARNING if WP_DEBUG]
    N --> O["loop tries = 1..5"]
    O --> P{"db_connect(false) ok?"}
    P -->|yes| Q[restore error_reporting<br/>return true]
    P -->|no| R["sleep(1)"]
    R --> S{tries &lt; 5?}
    S -->|yes| O
    S -->|no| T{"did_action('template_redirect')?"}
    T -->|yes| U[return false silently<br/>output already started]
    T -->|no| V{allow_bail?}
    V -->|no| U
    V -->|yes| W[["render 'Error reconnecting'<br/>page and bail()"]]

    style E fill:#c62828,color:#fff
    style W fill:#c62828,color:#fff
    style J fill:#2e7d32,color:#fff
    style M fill:#2e7d32,color:#fff
    style Q fill:#2e7d32,color:#fff
```

## Write path — charset and length validation

```mermaid
flowchart LR
    A["insert / replace / update / delete"] --> B["process_fields(table, data, format)"]
    B --> C["process_field_formats()<br/>format from arg, else field_types, else %s"]
    C --> D["process_field_charsets()<br/>get_col_charset() — memoized"]
    D --> E["process_field_lengths()<br/>get_col_length() — memoized"]
    E --> F{"value representable<br/>in column charset<br/>and within length?"}
    F -->|no| G[["return false —<br/>write REFUSED"]]
    F -->|yes| H["build SQL, prepare(), query()"]

    style G fill:#c62828,color:#fff
    style H fill:#2e7d32,color:#fff
```
