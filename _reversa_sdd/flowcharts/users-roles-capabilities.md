# Flowchart — `users-roles-capabilities`

> 🟢 CONFIRMED — derived from `wp-includes/capabilities.php` and `wp-includes/class-wp-user.php`

## The three-layer authorization model

```mermaid
flowchart TD
    A["current_user_can('edit_post', 42)"] --> B["META CAPABILITY<br/>object-specific question<br/>never stored anywhere"]
    B --> C["map_meta_cap()<br/>inspects the post's author,<br/>status and type"]
    C --> D["PRIMITIVE CAPABILITIES<br/>e.g. ['edit_posts',<br/>'edit_others_posts',<br/>'edit_published_posts']"]
    D --> E["WP_User::allcaps<br/>booleans from the ROLE"]
    E --> F["ROLE<br/>stored in wp_usermeta<br/>key {prefix}capabilities"]

    style B fill:#7b1fa2,color:#fff
    style D fill:#1565c0,color:#fff
    style F fill:#2e7d32,color:#fff
```

## `WP_User::has_cap()` — the gate

```mermaid
flowchart TD
    A["has_cap(cap, ...args)"] --> B{"is_numeric(cap)?"}
    B -->|yes| C["_deprecated_argument()<br/>translate_level_to_cap()<br/>← legacy user levels"]
    B -->|no| D
    C --> D["① caps = map_meta_cap(cap, ID, ...args)"]

    D --> E{"is_multisite()<br/>AND is_super_admin(ID)?"}
    E -->|yes| F{"'do_not_allow' in caps?"}
    F -->|yes| G[["return FALSE"]]
    F -->|no| H[["② return TRUE<br/>super admin bypasses<br/>everything else"]]
    E -->|no| I["③ capabilities = apply_filters(<br/>'user_has_cap',<br/>this-&gt;allcaps, caps, args, this)"]

    I --> J[["⚠️ ANY plugin can rewrite<br/>the entire capability set here"]]
    J --> K["capabilities['exist'] = true<br/>everyone is allowed to exist"]
    K --> L["④ unset(capabilities['do_not_allow'])<br/>the DENY primitive —<br/>can never be satisfied"]

    L --> M["⑤ array_all(caps, fn(c) =&gt;<br/>! empty(capabilities[c]))"]
    M --> N{"ALL mapped caps held?"}
    N -->|yes| O[allowed]
    N -->|no| P[denied]

    Q["NOTE: caps == [] ⇒ array_all is TRUE<br/>an empty requirement list means ALLOWED"]

    style G fill:#c62828,color:#fff
    style H fill:#ef6c00,color:#fff
    style J fill:#c62828,color:#fff
    style L fill:#1565c0,color:#fff
    style O fill:#2e7d32,color:#fff
    style P fill:#616161,color:#fff
    style Q fill:#ef6c00,color:#fff
```

## `map_meta_cap()` — representative cases

```mermaid
flowchart TD
    A["map_meta_cap(cap, user_id, ...args)"] --> B{switch cap}

    B -->|remove_user| C{"args[0] === user_id<br/>AND NOT super_admin?"}
    C -->|yes| D["'do_not_allow'<br/>cannot remove yourself<br/>in multisite"]
    C -->|no| E["'remove_users'"]

    B -->|"edit_user / edit_users"| F{"user_id &lt; 1?"}
    F -->|yes| G["'do_not_allow'<br/>a non-user cannot edit<br/>anyone, not even themselves"]
    F -->|no| H{"cap == 'edit_user'<br/>AND args[0] === user_id?"}
    H -->|yes| I[["break with EMPTY caps<br/>⇒ SELF-EDIT ALWAYS ALLOWED"]]
    H -->|no| J{"multisite AND<br/>(editing a super admin without being one<br/>OR lacking manage_network_users)?"}
    J -->|yes| G
    J -->|no| K["'edit_users'"]

    B -->|"delete_post / delete_page"| L{"args[0] set?"}
    L -->|"NO"| M[["_doing_it_wrong()<br/>'must always check against<br/>a specific post'<br/>→ 'do_not_allow'<br/><br/>FAIL CLOSED (added 6.1)"]]
    L -->|yes| N["get_post(args[0])<br/>branch on:<br/>• post type exists<br/>• post type map_meta_cap flag<br/>• author == user?<br/>&nbsp;&nbsp;delete_posts vs delete_others_posts<br/>• status published/private?<br/>&nbsp;&nbsp;delete_published_posts<br/>&nbsp;&nbsp;delete_private_posts<br/>• is it in the trash?"]

    style D fill:#c62828,color:#fff
    style G fill:#c62828,color:#fff
    style I fill:#2e7d32,color:#fff
    style M fill:#ef6c00,color:#fff
```

## Role hierarchy

```mermaid
flowchart TD
    A["administrator<br/>manage_options · edit_users · create_users<br/>activate_plugins · edit_plugins · install_plugins<br/>switch_themes · edit_themes · install_themes<br/>update_core · export · import · edit_dashboard"] --> B
    B["editor<br/>edit_others_posts · delete_others_posts<br/>edit_others_pages · publish_pages<br/>read_private_posts · read_private_pages<br/>manage_categories · manage_links<br/>moderate_comments · unfiltered_html"] --> C
    C["author<br/>publish_posts · edit_published_posts<br/>delete_published_posts · upload_files"] --> D
    D["contributor<br/>edit_posts · delete_posts · read<br/><br/>⚠️ CANNOT publish<br/>⚠️ CANNOT upload files"] --> E
    E["subscriber<br/>read"]

    F["super admin (multisite only)<br/>bypasses has_cap() entirely<br/>except do_not_allow"] -.->|outranks| A
    G["$super_admins PHP global<br/>outranks the site_admins<br/>network option"] -.-> F

    style A fill:#c62828,color:#fff
    style D fill:#ef6c00,color:#fff
    style F fill:#7b1fa2,color:#fff
    style G fill:#7b1fa2,color:#fff
```

## Dynamic capability grants — compute, don't store

```mermaid
flowchart LR
    A["apply_filters('user_has_cap', allcaps, …)"] --> B["wp_maybe_grant_install_languages_cap()<br/>→ install_languages<br/>when the filesystem permits"]
    A --> C["wp_maybe_grant_resume_extensions_caps()<br/>→ resume_plugin / resume_theme<br/>only in recovery mode"]
    A --> D["wp_maybe_grant_site_health_caps()<br/>→ view_site_health_checks"]

    E["The sanctioned pattern for<br/>environment-dependent capabilities:<br/>never persisted to wp_usermeta"]

    style E fill:#1565c0,color:#fff
```
