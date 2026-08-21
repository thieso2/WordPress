# Flowchart — `metadata`

> 🟢 CONFIRMED — derived from `wp-includes/meta.php`

## Type-to-table dispatch

```mermaid
flowchart LR
    A["meta_type string"] --> B["_get_meta_table(type)<br/>table_name = type . 'meta'"]
    B --> C{"$wpdb->{table_name}<br/>non-empty?"}
    C -->|no| D[["return false<br/>operation aborts"]]
    C -->|yes| E[table resolved]

    E --> F["'post' → wp_postmeta"]
    E --> G["'user' → wp_usermeta"]
    E --> H["'comment' → wp_commentmeta"]
    E --> I["'term' → wp_termmeta"]
    E --> J["'blog' → wp_blogmeta"]

    E --> K["column = sanitize_key(type . '_id')"]

    style D fill:#c62828,color:#fff
```

## `add_metadata()` — including the unique-check race

```mermaid
flowchart TD
    A["add_metadata(type, object_id, key, value, unique)"] --> B{type AND key AND<br/>is_numeric object_id?}
    B -->|no| C[return false]
    B -->|yes| D["object_id = absint()"]
    D --> E{object_id == 0?}
    E -->|yes| C
    E -->|no| F["table = _get_meta_table(type)"]
    F --> G{table false?}
    G -->|yes| C
    G -->|no| H["subtype = get_object_subtype()"]

    H --> I["key = wp_unslash(key)<br/>value = wp_unslash(value)<br/>← input arrives SLASHED"]
    I --> J["value = sanitize_meta(key, value, type, subtype)"]
    J --> K["apply_filters add_{type}_metadata"]
    K --> L{"!== null?"}
    L -->|yes| M[["RETURN filter result<br/>full short-circuit"]]
    L -->|no| N{unique requested?}

    N -->|yes| O["SELECT COUNT(*) FROM table<br/>WHERE meta_key = %s<br/>AND column = %d"]
    O --> P{count &gt; 0?}
    P -->|yes| C
    P -->|no| Q[["⚠️ RACE WINDOW<br/>no unique index on<br/>(object_id, meta_key)"]]
    N -->|no| R
    Q --> R["value = maybe_serialize(value)<br/>do_action add_{type}_meta"]

    R --> S["$wpdb->insert(table, {column, meta_key, meta_value})"]
    S --> T{result?}
    T -->|no| C
    T -->|yes| U["wp_cache_delete(object_id, '{type}_meta')<br/>do_action added_{type}_meta"]
    U --> V[return meta_id]

    style M fill:#1565c0,color:#fff
    style Q fill:#ef6c00,color:#fff
    style V fill:#2e7d32,color:#fff
```

## `get_metadata_raw()` — read path

```mermaid
flowchart TD
    A["get_metadata_raw(type, object_id, key, single)"] --> B{type AND numeric object_id?}
    B -->|no| C[return false]
    B -->|yes| D["apply_filters get_{type}_metadata"]
    D --> E{"!== null?"}
    E -->|yes| F{"single AND is_array(check)?"}
    F -->|yes| G[["return check[0]"]]
    F -->|no| H[["return check"]]

    E -->|no| I["wp_cache_get(object_id, '{type}_meta')"]
    I --> J{cache hit?}
    J -->|no| K["update_meta_cache(type, [object_id])<br/>loads ALL meta for the object"]
    J -->|yes| L
    K --> L{meta_key given?}
    L -->|no| M[return the whole meta_cache]
    L -->|yes| N{"isset(meta_cache[key])?"}
    N -->|no| O["return null<br/>→ get_metadata() then tries<br/>get_metadata_default()"]
    N -->|yes| P{single?}
    P -->|yes| Q["maybe_unserialize(values[0])"]
    P -->|no| R["array_map('maybe_unserialize', values)"]

    style G fill:#1565c0,color:#fff
    style H fill:#1565c0,color:#fff
    style Q fill:#2e7d32,color:#fff
    style R fill:#2e7d32,color:#fff
```

## `update_meta_cache()` — the N+1 defense

```mermaid
flowchart TD
    A["update_meta_cache(type, object_ids)"] --> B{type AND object_ids?}
    B -->|no| C[return false]
    B -->|yes| D["table = _get_meta_table(type)<br/>column = sanitize_key(type.'_id')"]
    D --> E{object_ids is array?}
    E -->|no| F["preg_replace '|[^0-9,]|' → explode(',')"]
    E -->|yes| G
    F --> G["array_map('intval', object_ids)"]
    G --> H["apply_filters update_{type}_metadata_cache"]
    H --> I{"!== null?"}
    I -->|yes| J[["return (bool) check"]]
    I -->|no| K["wp_cache_get_multiple(object_ids, '{type}_meta')"]

    K --> L[partition into<br/>cached / non_cached_ids]
    L --> M{non_cached_ids empty?}
    M -->|yes| N[return cache]
    M -->|no| O["ONE QUERY:<br/>SELECT column, meta_key, meta_value<br/>FROM table<br/>WHERE column IN (ids)<br/>ORDER BY meta_id ASC<br/>(umeta_id for users)"]

    O --> P["group rows into<br/>array&lt;id, array&lt;key, value[]&gt;&gt;<br/>insertion order preserved"]
    P --> Q["wp_cache_add per object id"]
    Q --> R[return cache]

    style O fill:#1565c0,color:#fff
    style N fill:#2e7d32,color:#fff
    style R fill:#2e7d32,color:#fff
```

## Protected-meta determination

```mermaid
flowchart LR
    A["is_protected_meta(key, type)"] --> B["preg_replace<br/>/[^\x20-\x7E\p{L}]/ → ''<br/><br/>strips NUL, zero-width space,<br/>control chars — anything that is not<br/>printable ASCII or a Unicode letter"]
    B --> C{"strlen(sanitized) &gt; 0<br/>AND sanitized[0] === '_'?"}
    C -->|yes| D[protected = true]
    C -->|no| E[protected = false]
    D --> F["apply_filters('is_protected_meta',<br/>protected, key, type)"]
    E --> F
    F --> G["hidden from custom-fields UI<br/>and from REST<br/><br/>⚠️ NOT enforced at storage layer"]

    style G fill:#ef6c00,color:#fff
```
