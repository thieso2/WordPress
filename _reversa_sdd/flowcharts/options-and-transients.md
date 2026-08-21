# Flowchart — `options-and-transients`

> 🟢 CONFIRMED — derived from `wp-includes/option.php`

## `get_option()` — five-level read cascade

```mermaid
flowchart TD
    A["get_option(option, default)"] --> B["trim(option)"]
    B --> C{empty?}
    C -->|yes| D[return false]
    C -->|no| E{deprecated key?<br/>blacklist_keys<br/>comment_whitelist}
    E -->|yes| F["_deprecated_argument()<br/>recurse with new name"]
    E -->|no| G["① apply_filters pre_option_{option}<br/>then pre_option"]

    G --> H{"result !== false?"}
    H -->|yes| I[["RETURN — DB never touched"]]
    H -->|no| J{WP_SETUP_CONFIG defined?}
    J -->|yes| D
    J -->|no| K["passed_default = func_num_args() &gt; 1"]

    K --> L["② wp_load_alloptions()"]
    L --> M{"option in alloptions?"}
    M -->|yes| N[value found]
    M -->|no| O["③ wp_cache_get('notoptions')"]

    O --> P{"option in notoptions?"}
    P -->|yes| Q[["RETURN default_option_{option}<br/>NO DB QUERY"]]
    P -->|no| R["④ wp_cache_get(option, 'options')"]

    R --> S{cache hit?}
    S -->|yes| N
    S -->|no| T["⑤ SELECT option_value<br/>FROM wp_options<br/>WHERE option_name = %s LIMIT 1<br/><br/>get_row() not get_var() —<br/>0/false/null ambiguity"]

    T --> U{row is object?}
    U -->|yes| V["wp_cache_add(option, value)"]
    U -->|no| W["notoptions[option] = true<br/>wp_cache_set('notoptions')"]
    W --> Q
    V --> N

    N --> X{"option == 'home'<br/>AND value == ''?"}
    X -->|yes| Y["return get_option('siteurl')"]
    X -->|no| Z["maybe_unserialize()<br/>apply_filters option_{option}"]
    Z --> AA[return value]

    style I fill:#1565c0,color:#fff
    style Q fill:#616161,color:#fff
    style AA fill:#2e7d32,color:#fff
    style T fill:#ef6c00,color:#fff
```

## `update_option()` — write path

```mermaid
flowchart TD
    A["update_option(option, value, autoload)"] --> B[trim; empty → false]
    B --> C[deprecated key remap]
    C --> D{"option is<br/>'alloptions' or 'notoptions'?"}
    D -->|yes| E[["wp_die() — protected"]]
    D -->|no| F{value is object?}
    F -->|yes| G["clone value"]
    F -->|no| H
    G --> H["sanitize_option(option, value)"]
    H --> I["old_value = get_option(option)"]
    I --> J["pre_update_option_{option}<br/>then pre_update_option"]

    J --> K{"value === old_value OR<br/>maybe_serialize equal?"}
    K -->|yes| L[["RETURN FALSE<br/>'unchanged' looks like 'failed'"]]
    K -->|no| M{"default_option_{option}<br/>=== old_value?"}
    M -->|yes| N[["delegate to add_option()<br/>option did not really exist"]]
    M -->|no| O["serialized = maybe_serialize(value)<br/>do_action('update_option')"]

    O --> P{autoload argument}
    P -->|"not null"| Q["wp_determine_option_autoload_value()"]
    P -->|"null"| R["SELECT autoload<br/>FROM wp_options"]
    R --> S{"raw autoload in<br/>auto-on / auto-off / auto?"}
    S -->|yes| T["re-evaluate heuristic<br/>update only if changed"]
    S -->|"no — explicit on/off"| U["LEAVE UNTOUCHED<br/>human intent wins"]

    Q --> V
    T --> V
    U --> V["$wpdb->update(wp_options)"]
    V --> W{result?}
    W -->|falsy| L2[return false]
    W -->|ok| X[remove from notoptions<br/>refresh alloptions or per-option cache]
    X --> Y["do_action update_option_{option}<br/>do_action updated_option"]
    Y --> Z[return true]

    style E fill:#c62828,color:#fff
    style L fill:#ef6c00,color:#fff
    style U fill:#1565c0,color:#fff
    style Z fill:#2e7d32,color:#fff
```

## Autoload value determination

```mermaid
flowchart TD
    A["wp_determine_option_autoload_value(<br/>option, value, serialized, autoload)"] --> B{autoload is bool?}
    B -->|true| C["'on'"]
    B -->|false| D["'off'"]
    B -->|not bool| E{string value}

    E -->|"'on' or 'yes'"| C
    E -->|"'off' or 'no'"| D
    E -->|other| F["apply_filters('wp_default_autoload_value',<br/>null, option, value, serialized)"]

    F --> G["core callback:<br/>wp_filter_default_autoload_value_via_option_size"]
    G --> H["max = apply_filters(<br/>'wp_max_autoloaded_option_size', 150000)"]
    H --> I{"strlen(serialized) &gt; max?"}
    I -->|yes| J[return false]
    I -->|no| K[pass through]

    J --> L{filter result is bool?}
    K --> L
    L -->|"true"| M["'auto-on'"]
    L -->|"false"| N["'auto-off'<br/>oversized option<br/>excluded from every request"]
    L -->|"not bool"| O["'auto'"]

    style C fill:#2e7d32,color:#fff
    style D fill:#616161,color:#fff
    style M fill:#2e7d32,color:#fff
    style N fill:#ef6c00,color:#fff
    style O fill:#1565c0,color:#fff
```

## Transient storage — two backends

```mermaid
flowchart TD
    A["set_transient(name, value, expiration)"] --> B["pre_set_transient_{name}<br/>expiration_of_transient_{name}"]
    B --> C{"wp_using_ext_object_cache()<br/>OR wp_installing()?"}

    C -->|yes| D["wp_cache_set(name, value,<br/>'transient', expiration)<br/><br/>NO DATABASE ROWS"]
    C -->|no| E{"_transient_{name}<br/>option exists?"}

    E -->|no| F{expiration set?}
    F -->|yes| G["add_option(_transient_timeout_{name},<br/>time()+exp, autoload=false)<br/>add_option(_transient_{name},<br/>value, autoload=FALSE)"]
    F -->|no| H["add_option(_transient_{name},<br/>value, autoload=TRUE)<br/><br/>no expiry ⇒ autoloaded"]

    E -->|yes| I{expiration set?}
    I -->|no| J["update_option(_transient_{name})"]
    I -->|yes| K{"timeout row exists?"}
    K -->|no| L["REPAIR:<br/>delete value row,<br/>re-add both rows"]
    K -->|yes| M["update_option(timeout)<br/>update_option(value)"]

    D --> N["do_action set_transient_{name}<br/>do_action setted_transient"]
    G --> N
    H --> N
    J --> N
    L --> N
    M --> N

    style D fill:#1565c0,color:#fff
    style H fill:#ef6c00,color:#fff
    style L fill:#7b1fa2,color:#fff
    style N fill:#2e7d32,color:#fff
```

## Transient read and lazy expiry

```mermaid
flowchart TD
    A["get_transient(name)"] --> B["pre_transient_{name} filter"]
    B --> C{"!== false?"}
    C -->|yes| D[["RETURN short-circuit"]]
    C -->|no| E{"ext object cache<br/>or installing?"}

    E -->|yes| F["wp_cache_get(name, 'transient')<br/>native TTL handles expiry"]
    E -->|no| G["wp_load_alloptions()"]

    G --> H{"_transient_{name}<br/>in alloptions?"}
    H -->|yes| I["autoloaded ⇒ no timeout<br/>skip expiry check"]
    H -->|no| J["prime caches for<br/>value + timeout options<br/>timeout = get_option(_transient_timeout_{name})"]

    J --> K{"timeout !== false<br/>AND timeout &lt; time()?"}
    K -->|yes| L["delete_option(_transient_{name})<br/>delete_option(_transient_timeout_{name})<br/>value = false"]
    K -->|no| M
    I --> M["value = get_option(_transient_{name})"]

    F --> N
    L --> N
    M --> N["apply_filters transient_{name}"]
    N --> O[return value]

    style D fill:#1565c0,color:#fff
    style L fill:#ef6c00,color:#fff
    style O fill:#2e7d32,color:#fff
```
