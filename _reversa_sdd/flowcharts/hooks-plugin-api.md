# Flowchart — `hooks-plugin-api`

> 🟢 CONFIRMED — derived from `wp-includes/plugin.php` and `wp-includes/class-wp-hook.php`

## Dispatch: `apply_filters()` / `do_action()`

```mermaid
flowchart TD
    A["apply_filters(hook, value, ...args)"] --> B[increment wp_filters counter]
    B --> C{"wp_filter['all'] set?"}
    C -->|yes| D[push hook onto wp_current_filter<br/>_wp_call_all_hook with all args]
    C -->|no| E
    D --> E{"wp_filter[hook] set?"}
    E -->|no| F[pop current_filter if pushed<br/>return value unchanged]
    E -->|yes| G[push hook onto wp_current_filter<br/>if not already pushed]
    G --> H["unshift value onto args"]
    H --> I["WP_Hook::apply_filters(value, args)"]
    I --> J[pop wp_current_filter]
    J --> K[return filtered value]

    style F fill:#616161,color:#fff
    style K fill:#2e7d32,color:#fff
```

## `WP_Hook::apply_filters()` — the engine

```mermaid
flowchart TD
    A[enter] --> B{callbacks empty?}
    B -->|yes| C[return value unchanged]
    B -->|no| D["level = nesting_level++"]
    D --> E["iterations[level] = priorities<br/>(snapshot)"]
    E --> F["num_args = count(args)"]
    F --> G["priority = current(iterations[level])"]

    G --> H[for each callback at this priority]
    H --> I{doing_action?}
    I -->|no — filter| J["args[0] = value<br/>(chain previous result)"]
    I -->|yes — action| K
    J --> K{accepted_args}

    K -->|"== 0"| L["call_user_func(fn)"]
    K -->|">= num_args"| M["call_user_func_array(fn, args)"]
    K -->|"&lt; num_args"| N["call_user_func_array(fn,<br/>array_slice(args, 0, accepted_args))"]

    L --> O[value = result]
    M --> O
    N --> O
    O --> P{more callbacks<br/>at this priority?}
    P -->|yes| H
    P -->|no| Q{"next(iterations[level])<br/>!== false?"}
    Q -->|yes| G
    Q -->|no| R["unset iteration state<br/>nesting_level--"]
    R --> S[return value]

    style C fill:#616161,color:#fff
    style S fill:#2e7d32,color:#fff
```

## Registration and callback identity

```mermaid
flowchart TD
    A["add_filter(hook, cb, priority, accepted_args)"] --> B{priority === null?}
    B -->|yes| C[priority = 0]
    B -->|no| D
    C --> D["_wp_filter_build_unique_id(hook, cb, priority)"]

    D --> E{callback type}
    E -->|string| F[idx = the string]
    E -->|object| G["idx = spl_object_id(cb)"]
    E -->|"[object, method]"| H["idx = spl_object_id(obj) . method"]
    E -->|"[Class, method]"| I["idx = Class::method"]
    E -->|other| J[["idx = null<br/>SILENTLY DROPPED"]]

    F --> K
    G --> K
    H --> K
    I --> K["callbacks[priority][idx] =<br/>{function, accepted_args}"]

    K --> L{new priority AND<br/>more than 1 priority?}
    L -->|yes| M["ksort(callbacks, SORT_NUMERIC)"]
    L -->|no| N
    M --> N[refresh priorities cache]
    N --> O{nesting_level &gt; 0?<br/>hook is running now}
    O -->|yes| P["resort_active_iterations(<br/>priority, priority_existed)"]
    O -->|no| Q[done]
    P --> Q

    style J fill:#c62828,color:#fff
    style Q fill:#2e7d32,color:#fff
```

## Live re-sort while the hook is executing

```mermaid
flowchart TD
    A["resort_active_iterations(new_priority, priority_existed)"] --> B[for each active nesting level]
    B --> C["current = current_priority[level]"]
    C --> D[iteration = rebuilt priority list]
    D --> E{"current &lt; min priority?"}
    E -->|yes| F["array_unshift(iteration, current)<br/>continue"]
    E -->|no| G["walk next() until<br/>current(iteration) &gt;= current"]
    G --> H{"new_priority == current_priority[level]<br/>AND priority did NOT exist before?"}
    H -->|no| I[done for this level]
    H -->|yes| J{"current(iteration) === false?"}
    J -->|yes| K["prev = end(iteration)"]
    J -->|no| L["prev = prev(iteration)"]
    K --> M
    L --> M{"prev === false?"}
    M -->|yes| N["reset(iteration)<br/>start of array"]
    M -->|no| O{"new_priority !== prev?"}
    O -->|yes| P["next(iteration)<br/>move forward again"]
    O -->|no| Q[stay — callback will run this pass]
    N --> I
    P --> I
    Q --> I

    style Q fill:#2e7d32,color:#fff
```

## Plugin lifecycle registration

```mermaid
flowchart LR
    A["register_activation_hook(file, cb)"] --> B["plugin_basename(file)"]
    B --> C["add_action('activate_' . basename, cb)"]

    D["register_deactivation_hook(file, cb)"] --> E["plugin_basename(file)"]
    E --> F["add_action('deactivate_' . basename, cb)"]

    G["register_uninstall_hook(file, cb)"] --> H{"cb is [object, method]?"}
    H -->|yes| I[["_doing_it_wrong()<br/>return — rejected"]]
    H -->|no| J["get_option('uninstall_plugins')"]
    J --> K{already registered<br/>with same callback?}
    K -->|yes| L[no-op]
    K -->|no| M["update_option('uninstall_plugins', …)<br/>callback is SERIALIZED to DB"]

    style I fill:#c62828,color:#fff
    style M fill:#ef6c00,color:#fff
```
