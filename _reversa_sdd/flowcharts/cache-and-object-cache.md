# Flowchart — `cache-and-object-cache`

> 🟢 CONFIRMED — derived from `wp-includes/cache.php` and `wp-includes/class-wp-object-cache.php`

## Backend selection at boot

```mermaid
flowchart TD
    A["wp_start_object_cache()"] --> B{"wp-content/object-cache.php<br/>drop-in exists?"}
    B -->|yes| C["load the drop-in<br/>wp_using_ext_object_cache() = true"]
    B -->|no| D["new WP_Object_Cache()<br/>wp_using_ext_object_cache() = false"]

    C --> E["PERSISTENT<br/>survives requests<br/>honors $expire<br/>transients bypass the DB"]
    D --> F["REQUEST-SCOPED<br/>a PHP array<br/>$expire IGNORED<br/>transients stored in wp_options"]

    E --> G["wp_cache_add_global_groups(22 groups)<br/>wp_cache_add_non_persistent_groups(<br/>counts, plugins, theme_json)"]
    F --> G

    style E fill:#2e7d32,color:#fff
    style F fill:#ef6c00,color:#fff
```

## `WP_Object_Cache::get()`

```mermaid
flowchart TD
    A["get(key, group, force, &found)"] --> B{"is_valid_key(key)?<br/>int, or non-empty trimmed string"}
    B -->|no| C[["_doing_it_wrong()<br/>return false"]]
    B -->|yes| D{group empty?}
    D -->|yes| E["group = 'default'"]
    D -->|no| F
    E --> F{"multisite AND<br/>group NOT global?"}
    F -->|yes| G["key = blog_prefix . key<br/>('{blog_id}:')"]
    F -->|no| H
    G --> H{"_exists(key, group)?<br/>isset() OR array_key_exists()"}

    H -->|yes| I["found = true<br/>cache_hits++"]
    I --> J{value is object?}
    J -->|yes| K["return clone value"]
    J -->|no| L[return value]

    H -->|no| M["found = false<br/>cache_misses++<br/>return false"]

    style C fill:#c62828,color:#fff
    style K fill:#2e7d32,color:#fff
    style L fill:#2e7d32,color:#fff
    style M fill:#616161,color:#fff
```

## The `false` / `null` ambiguity

```mermaid
flowchart TD
    A["wp_cache_get(key, group)<br/>returns false"] --> B{Which is it?}
    B --> C["cache MISS<br/>nothing stored"]
    B --> D["cache HIT<br/>the stored value IS false"]

    C --> E["caller should query the source"]
    D --> F["caller should use the false"]

    G["The only reliable discriminator:"] --> H["wp_cache_get(key, group, false, $found)<br/>then check $found"]

    I["Why _exists() needs array_key_exists():"] --> J["isset() returns false for a stored null<br/>→ a cached null would look like a miss<br/>→ array_key_exists() disambiguates"]

    style D fill:#ef6c00,color:#fff
    style H fill:#2e7d32,color:#fff
    style J fill:#1565c0,color:#fff
```

## Multisite key isolation

```mermaid
flowchart LR
    subgraph Global["Global groups — NOT prefixed"]
        A1["users"] --> A2["key: 'user_42'"]
        A3["sites"] --> A4["key: 'site_1'"]
        A5["site-transient"] --> A6["shared across all blogs"]
    end

    subgraph Local["Non-global groups — prefixed"]
        B1["posts, blog 3"] --> B2["key: '3:post_15'"]
        B3["posts, blog 7"] --> B4["key: '7:post_15'"]
        B5["different rows,<br/>same logical id"]
    end

    C["switch_to_blog(id)"] --> D["blog_prefix = id . ':'<br/>subsequent non-global keys<br/>land in the other namespace"]

    style A6 fill:#1565c0,color:#fff
    style B5 fill:#2e7d32,color:#fff
```
