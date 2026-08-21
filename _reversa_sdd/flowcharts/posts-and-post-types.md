# Flowchart — `posts-and-post-types`

> 🟢 CONFIRMED — derived from `wp-includes/post.php`

## Status derived from date — the core rule

```mermaid
flowchart TD
    A["wp_insert_post(postarr)"] --> B["resolve post_date / post_date_gmt<br/>via wp_resolve_post_date()"]
    B --> C{"caller-supplied post_status"}

    C -->|"'publish'"| D{"strtotime(post_date_gmt)<br/>- strtotime(now)<br/>&gt;= 60 seconds?"}
    D -->|yes| E["post_status = 'future'<br/>SILENTLY RESCHEDULED"]
    D -->|no| F["stays 'publish'"]

    C -->|"'future'"| G{"strtotime(post_date_gmt)<br/>- strtotime(now)<br/>&lt; 60 seconds?"}
    G -->|yes| H["post_status = 'publish'<br/>SILENTLY PUBLISHED"]
    G -->|no| I["stays 'future'"]

    C -->|"other"| J[unchanged]

    E --> K[continue insert]
    F --> K
    H --> K
    I --> K
    J --> K

    style E fill:#ef6c00,color:#fff
    style H fill:#ef6c00,color:#fff
```

## `wp_insert_post()` — write pipeline

```mermaid
flowchart TD
    A["wp_insert_post(postarr, wp_error, fire_after_hooks)"] --> B["capture unsanitized copy<br/>merge defaults<br/>post_status='draft', post_type='post'"]
    B --> C{"post_type == 'attachment'<br/>AND status NOT IN<br/>(inherit, private, trash, auto-draft)?"}
    C -->|yes| D[["WP_Error / false"]]
    C -->|no| E["wp_resolve_post_date()"]

    E --> F{"post_date_gmt empty<br/>or 0000-00-00?"}
    F -->|yes| G{status is draft-like?}
    G -->|yes| H["post_date_gmt =<br/>'0000-00-00 00:00:00'<br/>← needs NO_ZERO_DATE off"]
    G -->|no| I["get_gmt_from_date(post_date)"]
    F -->|no| J
    H --> J
    I --> J["status ↔ date coupling<br/>(see previous diagram)"]

    J --> K{"post_name empty AND status NOT IN<br/>(draft, pending, auto-draft)?"}
    K -->|yes| L["sanitize_title(post_title)<br/>→ wp_unique_post_slug()"]
    K -->|no| M
    L --> M["apply_filters wp_insert_post_data"]

    M --> N{update or insert?}
    N -->|insert| O["$wpdb->insert(wp_posts)"]
    N -->|update| P["$wpdb->update(wp_posts)"]

    O --> Q["set post meta, terms,<br/>post format, thumbnail"]
    P --> Q
    Q --> R{status changed?}
    R -->|yes| S["wp_transition_post_status(<br/>new, old, post)"]
    R -->|no| T
    S --> T["do_action save_post_{post_type}<br/>do_action save_post<br/>do_action wp_insert_post"]
    T --> U[return post ID]

    style D fill:#c62828,color:#fff
    style H fill:#7b1fa2,color:#fff
    style U fill:#2e7d32,color:#fff
```

## `wp_unique_post_slug()` — three uniqueness scopes

```mermaid
flowchart TD
    A["wp_unique_post_slug(slug, id, status, type, parent)"] --> B{"status IN (draft, pending, auto-draft)<br/>OR (inherit AND revision)<br/>OR type == user_request?"}
    B -->|yes| C[["return slug UNCHANGED<br/>no uniqueness enforced"]]
    B -->|no| D["pre_wp_unique_post_slug filter"]
    D --> E{"!== null?"}
    E -->|yes| F[["return override"]]
    E -->|no| G{post type}

    G -->|attachment| H["SCOPE: ALL post types<br/>WHERE post_name = %s AND ID != %d"]
    G -->|hierarchical| I{"type == nav_menu_item?"}
    I -->|yes| C
    I -->|no| J["SCOPE: (type, parent) + attachment<br/>WHERE post_name = %s<br/>AND post_type IN (%s,'attachment')<br/>AND ID != %d AND post_parent = %d"]
    G -->|flat| K["SCOPE: within post type<br/>WHERE post_name = %s<br/>AND post_type = %s AND ID != %d"]

    H --> L
    J --> L
    K --> L{"collision OR<br/>slug in wp_rewrite-&gt;feeds OR<br/>slug == 'embed' OR<br/>matches ^(pagination_base)?\d+$ OR<br/>conflicts with date archive?"}

    L -->|no| M[return slug as-is]
    L -->|yes| N["suffix = 2"]
    N --> O["alt = _truncate_post_slug(slug,<br/>200 - strlen(suffix) - 1) . '-suffix'"]
    O --> P["ONE QUERY per iteration"]
    P --> Q{still colliding?}
    Q -->|yes| R["suffix++"]
    R --> O
    Q -->|no| S[return alt slug]

    style C fill:#616161,color:#fff
    style F fill:#1565c0,color:#fff
    style P fill:#ef6c00,color:#fff
    style M fill:#2e7d32,color:#fff
    style S fill:#2e7d32,color:#fff
```

## Status transition side effects

```mermaid
flowchart TD
    A["wp_transition_post_status(new, old, post)"] --> B["do_action('transition_post_status',<br/>new, old, post)"]
    B --> C["do_action(\"{old}_to_{new}\", post)<br/><br/>11 statuses ⇒ up to 121<br/>undeclared hook names"]

    C --> D["core callback:<br/>_transition_post_status()"]

    D --> E{"old != 'publish'<br/>AND new == 'publish'?"}
    E -->|yes| F{"get_the_guid(post) empty?"}
    F -->|yes| G["UPDATE wp_posts SET guid =<br/>get_permalink(post-&gt;ID)<br/><br/>set once, never updated again"]
    F -->|no| H
    E -->|no| H{"new == 'publish'<br/>OR old == 'publish'?"}

    G --> H
    H -->|yes| I["for timezone in (server, gmt, blog):<br/>delete lastpostmodified:{tz}<br/>delete lastpostdate:{tz}<br/>delete lastpostdate:{tz}:{post_type}"]
    H -->|no| J
    I --> J{"new !== old?"}
    J -->|yes| K["delete post-count caches<br/>('counts' group — non-persistent)"]
    J -->|no| L
    K --> L["ALWAYS:<br/>wp_clear_scheduled_hook(<br/>'publish_future_post', [post-&gt;ID])<br/><br/>'in case the post status<br/>bounced from future to draft'"]
    L --> M{new status still 'future'?}
    M -->|yes| N[re-schedule publish_future_post]
    M -->|no| O[done]

    style C fill:#7b1fa2,color:#fff
    style G fill:#1565c0,color:#fff
    style L fill:#ef6c00,color:#fff
```

## The 16 built-in post types — one table

```mermaid
flowchart LR
    subgraph T["wp_posts — distinguished only by post_type"]
        direction TB
        A["PUBLIC<br/>post · page · attachment"]
        B["VERSIONING<br/>revision"]
        C["NAVIGATION<br/>nav_menu_item · wp_navigation"]
        D["CUSTOMIZER<br/>custom_css · customize_changeset"]
        E["BLOCK THEMES<br/>wp_template · wp_template_part<br/>wp_global_styles · wp_block"]
        F["FONT LIBRARY<br/>wp_font_family · wp_font_face"]
        G["INFRASTRUCTURE<br/>oembed_cache · user_request"]
    end

    H["Pattern: whenever WordPress needs<br/>to persist structured data it registers<br/>a post type rather than a table"]

    style A fill:#2e7d32,color:#fff
    style G fill:#ef6c00,color:#fff
    style H fill:#1565c0,color:#fff
```
