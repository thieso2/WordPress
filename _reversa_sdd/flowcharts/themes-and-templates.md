# Flowchart — `themes-and-templates`

> 🟢 CONFIRMED — derived from `wp-includes/template-loader.php` and `wp-includes/template.php`

## `template-loader.php` — the whole hierarchy

```mermaid
flowchart TD
    A["wp() has run<br/>template-loader.php included"] --> B{"wp_using_themes()?"}
    B -->|yes| C["do_action('template_redirect')"]
    B -->|no| D
    C --> D{"REQUEST_METHOD == 'HEAD'<br/>AND exit_on_http_head filter?"}
    D -->|yes| E[["exit — no body sent"]]
    D -->|no| F{special request?}

    F -->|is_robots| G["do_action('do_robots'); return"]
    F -->|is_favicon| H["do_action('do_favicon'); return"]
    F -->|is_feed| I["do_feed(); return"]
    F -->|is_trackback| J["require wp-trackback.php; return"]
    F -->|none| K{"wp_using_themes()?"}

    L["⬆ these four run EVEN WHEN<br/>themes are disabled"]

    K -->|no| M[nothing rendered]
    K -->|yes| N["walk the 17 conditionals IN ORDER"]

    N --> O["is_embed → is_404 → is_search →<br/>is_front_page → is_home → is_privacy_policy →<br/>is_post_type_archive → is_tax → is_attachment →<br/>is_single → is_page → is_singular →<br/>is_category → is_tag → is_author →<br/>is_date → is_archive"]

    O --> P{first conditional true?}
    P -->|yes| Q["template = its getter()"]
    Q --> R{"tag == 'is_attachment'?"}
    R -->|yes| S["remove_filter('the_content',<br/>'prepend_attachment')"]
    R -->|no| T
    S --> T[break]
    P -->|"none matched"| U["template = get_index_template()"]

    T --> V["apply_filters('template_include', template)"]
    U --> V
    V --> W["is_stringy check<br/>template = realpath((string) template)"]
    W --> X{"is_string AND<br/>ends with .php or .html AND<br/>is_file AND is_readable?"}
    X -->|no| Y["if current_user_can('switch_themes')<br/>show a theme error; else nothing"]
    X -->|yes| Z["do_action('wp_before_include_template')<br/>include template"]

    style E fill:#616161,color:#fff
    style L fill:#1565c0,color:#fff
    style O fill:#7b1fa2,color:#fff
    style X fill:#c62828,color:#fff
    style Z fill:#2e7d32,color:#fff
```

## Candidate list → file, for `is_single`

```mermaid
flowchart TD
    A["get_single_template()"] --> B["object = get_queried_object()"]
    B --> C["build candidates MOST SPECIFIC FIRST"]

    C --> D["1. page-template slug from post meta<br/>&nbsp;&nbsp;&nbsp;only if validate_file(slug) === 0<br/>&nbsp;&nbsp;&nbsp;⚠️ the sole guard against post meta<br/>&nbsp;&nbsp;&nbsp;selecting an arbitrary file"]
    D --> E["2. single-{post_type}-{urldecode(post_name)}.php<br/>&nbsp;&nbsp;&nbsp;ONLY when decoding changed the string"]
    E --> F["3. single-{post_type}-{post_name}.php"]
    F --> G["4. single-{post_type}.php"]
    G --> H["5. single.php"]

    H --> I["get_query_template('single', candidates)"]
    I --> J["type sanitized: preg_replace('|[^a-z0-9-]+|','')"]
    J --> K["apply_filters('single_template_hierarchy')"]
    K --> L["locate_template(candidates)"]
    L --> M["locate_block_template()<br/>block themes override last"]

    style D fill:#ef6c00,color:#fff
    style J fill:#1565c0,color:#fff
```

## `locate_template()` — filename specificity beats theme proximity

```mermaid
flowchart TD
    A["locate_template(names)"] --> B[for each candidate name<br/>IN ORDER]
    B --> C{"file_exists(<br/>wp_stylesheet_path/name )?<br/>← CHILD / active theme"}
    C -->|yes| D[["located — BREAK"]]
    C -->|no| E{"is_child_theme() AND<br/>file_exists(<br/>wp_template_path/name )?<br/>← PARENT theme"}
    E -->|yes| D
    E -->|no| F{"file_exists(<br/>wp-includes/theme-compat/name )?<br/>← core fallback"}
    F -->|yes| D
    F -->|no| G{more candidates?}
    G -->|yes| B
    G -->|no| H[return '']

    I[["THE CONSEQUENCE:<br/>the loop breaks on the first NAME that<br/>exists ANYWHERE. A parent theme's<br/>single-product.php beats a child theme's<br/>single.php — a child cannot override a<br/>more-specific parent template with a<br/>less-specific one."]]

    style D fill:#2e7d32,color:#fff
    style I fill:#ef6c00,color:#fff
```

## Parent/child: two opposite orderings

```mermaid
flowchart LR
    subgraph F["functions.php loading — wp-settings.php:740"]
        A["CHILD functions.php"] --> B["PARENT functions.php"]
        C["child first, so it can<br/>DECLARE functions the<br/>parent then checks for"]
    end

    subgraph T["template lookup — locate_template()"]
        D["CHILD template path"] --> E["PARENT template path"]
        F2["child first, so it can<br/>OVERRIDE the parent's file"]
    end

    G["Both orderings are 'child first',<br/>but for opposite reasons:<br/>functions must be declarable first,<br/>templates must be findable first."]

    style C fill:#1565c0,color:#fff
    style F2 fill:#1565c0,color:#fff
    style G fill:#7b1fa2,color:#fff
```
