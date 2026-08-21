# Flowchart — `query-and-loop`

> 🟢 CONFIRMED — derived from `wp-includes/class-wp.php` and `wp-includes/class-wp-query.php`

## `WP::main()` — the request pipeline

```mermaid
flowchart TD
    A["wp() → WP::main(query_args)"] --> B["init()<br/>set up current user"]
    B --> C["parse_request(query_args)"]
    C --> D{"do_parse_request filter<br/>returns true?"}
    D -->|no| E[["skip query, 404 and globals<br/>— how REST and admin-ajax<br/>avoid the main query"]]
    D -->|yes| F["match REQUEST_URI against<br/>wp_rewrite rules<br/>→ query_vars"]

    F --> G{parsed?}
    G -->|no| E
    G -->|yes| H["query_posts()<br/>wp_the_query-&gt;query(query_vars)"]
    H --> I["handle_404()"]
    I --> J["register_globals()<br/>$posts, $post, $wp_query"]
    J --> K
    E --> K["send_headers()"]
    K --> L["do_action_ref_array('wp', &amp;this)"]
    L --> M[template-loader.php]

    style E fill:#616161,color:#fff
    style M fill:#2e7d32,color:#fff
```

## Query-variable security boundary

```mermaid
flowchart LR
    A["?foo=bar in the URL"] --> B{"is 'foo' in<br/>public_query_vars?"}
    B -->|no| C[["DISCARDED<br/>never reaches WP_Query"]]
    B -->|yes| D[accepted into query_vars]

    E["private_query_vars<br/>post_status · post__in · fields<br/>perm · post_parent · offset<br/>posts_per_page · nopaging"] --> F["PHP-only.<br/>If post_status were public,<br/>?post_status=draft would<br/>expose unpublished content."]

    G["add_query_var('post_status')"] --> H[["one line breaches<br/>the boundary"]]

    style C fill:#616161,color:#fff
    style F fill:#1565c0,color:#fff
    style H fill:#c62828,color:#fff
```

## `handle_404()` — exemption cascade

```mermaid
flowchart TD
    A["handle_404()"] --> B{"pre_handle_404 filter<br/>returns non-false?"}
    B -->|yes| C[return — fully overridden]
    B -->|no| D{already is_404?}
    D -->|yes| C
    D -->|no| E["set_404 = TRUE (the default)"]

    E --> F{"is_admin() OR is_robots()<br/>OR is_favicon()?"}
    F -->|yes| G[set_404 = false]
    F -->|no| H{"wp_query-&gt;posts<br/>non-empty?"}

    H -->|yes| I[content_found = true]
    I --> J{is_singular AND<br/>query_vars page set?}
    J -->|yes| K{"post_content contains<br/>&lt;!--nextpage--&gt;?"}
    K -->|yes| L["content_found =<br/>page &lt;= substr_count + 1"]
    K -->|no| M["content_found = FALSE<br/>?page=2 on an<br/>unpaginated post"]
    J -->|no| N
    L --> N
    M --> N{is_posts_page AND<br/>page var set?}
    N -->|yes| O["content_found = FALSE<br/>posts page never<br/>supports nextpage"]
    N -->|no| P
    O --> P{content_found?}
    P -->|yes| G
    P -->|no| Q

    H -->|no| R{"is_paged()?"}
    R -->|"yes — /page/5/"| Q["ALWAYS 404<br/>no exemption on this branch"]
    R -->|no| S{"is_author AND numeric author &gt; 0<br/>AND is_user_member_of_blog<br/>OR<br/>(is_tag/is_category/is_tax/<br/>is_post_type_archive)<br/>AND get_queried_object()<br/>OR<br/>is_home / is_search / is_feed"}
    S -->|yes| G
    S -->|no| Q

    G --> T[serve 200]
    Q --> U["wp_query-&gt;set_404()<br/>status_header(404)<br/>nocache_headers()"]

    style C fill:#1565c0,color:#fff
    style M fill:#ef6c00,color:#fff
    style O fill:#ef6c00,color:#fff
    style Q fill:#c62828,color:#fff
    style T fill:#2e7d32,color:#fff
```

## `WP_Query::get_posts()` — SQL assembly and its 34 filters

```mermaid
flowchart TD
    A["get_posts()"] --> B["parse_query() → query_vars<br/>do_action('pre_get_posts')"]
    B --> C{"posts_pre_query filter<br/>returns non-null?"}
    C -->|yes| D[["BYPASS — use the<br/>filter's posts entirely"]]
    C -->|no| E[build seven clauses]

    E --> F["fields · join · where · groupby<br/>orderby · distinct · limits"]
    F --> G["EARLY filters:<br/>posts_fields, posts_join,<br/>posts_join_paged, posts_where,<br/>posts_where_paged, posts_groupby,<br/>posts_orderby, posts_distinct,<br/>post_limits, posts_clauses"]

    G --> H{"suppress_filters?"}
    H -->|yes| I[skip early set]
    H -->|no| J
    I --> J["LATE filters (*_request):<br/>posts_fields_request, posts_join_request,<br/>posts_where_request, posts_groupby_request,<br/>posts_orderby_request, posts_distinct_request,<br/>post_limits_request, posts_clauses_request"]

    J --> K["old_request = assembled SQL"]
    K --> L["apply_filters('posts_request', sql)"]
    L --> M{"old_request === request<br/>AND fields === 'wp_posts.*'?<br/>(is_unfiltered_query)"}

    M -->|no| N["split disabled —<br/>a plugin changed the SQL"]
    M -->|yes| O{"wp_using_ext_object_cache()<br/>OR (limits AND<br/>posts_per_page &lt; 500)?"}
    O -->|yes| P["split_the_query = true"]
    O -->|no| N

    P --> Q["apply_filters('split_the_query')"]
    Q --> R["SELECT ID FROM …<br/>then hydrate each post<br/>from the object cache"]
    N --> S["SELECT wp_posts.* FROM …<br/>one large result set"]

    R --> T["set_found_posts()"]
    S --> T
    T --> U["apply_filters('posts_results')"]
    U --> V["apply_filters('the_posts')"]
    V --> W[return posts]

    style D fill:#1565c0,color:#fff
    style R fill:#2e7d32,color:#fff
    style S fill:#ef6c00,color:#fff
    style W fill:#2e7d32,color:#fff
```

## Pagination cost — `set_found_posts()`

```mermaid
flowchart TD
    A["set_found_posts(query_vars, limits)"] --> B{"no_found_rows<br/>OR posts is empty array?"}
    B -->|yes| C[["return — found_posts stays 0<br/>THE FAST PATH"]]
    B -->|no| D{limits non-empty?}

    D -->|yes| E["apply_filters('found_posts_query',<br/>'SELECT FOUND_ROWS()')"]
    E --> F[["$wpdb->get_var(...)<br/><br/>requires SQL_CALC_FOUND_ROWS<br/>in the main query ⇒ MySQL counts<br/>the ENTIRE matching set"]]
    D -->|no| G["found_posts = count(posts)<br/>| 0 if null | 1 otherwise"]

    F --> H
    G --> H["apply_filters('found_posts')"]
    H --> I{limits non-empty?}
    I -->|yes| J["max_num_pages =<br/>ceil(found_posts / posts_per_page)"]
    I -->|no| K[done]
    J --> K

    style C fill:#2e7d32,color:#fff
    style F fill:#c62828,color:#fff
```

## The Loop — lazy cache priming

```mermaid
flowchart TD
    A["while ( have_posts() ) : the_post();"] --> B{"have_posts()"}
    B --> C{"current_post + 1<br/>&lt; post_count?"}
    C -->|yes| D[return true]
    C -->|no| E{"current_post + 1 == post_count<br/>AND post_count &gt; 0?"}
    E -->|yes| F["do_action('loop_end')<br/>rewind_posts()<br/>AUTO-REWIND"]
    E -->|no| G{post_count == 0?}
    G -->|yes| H["do_action('loop_no_results')"]
    F --> I[in_the_loop = false<br/>return false]
    H --> I

    D --> J["the_post()"]
    J --> K{"in_the_loop already true?"}
    K -->|yes| L[skip priming]
    K -->|"no — FIRST iteration"| M{"query_vars['fields']"}

    M -->|"'all'"| N[post objects already present]
    M -->|"'ids'"| O["post_ids = posts"]
    M -->|partial| P["array_reduce → collect IDs"]

    O --> Q
    P --> Q["_prime_post_caches(ids,<br/>update_post_term_cache,<br/>update_post_meta_cache)<br/><br/>ONE bulk term query<br/>ONE bulk meta query"]
    Q --> R["array_map('get_post', ids)"]
    N --> S
    R --> S["update_post_author_caches()<br/>ONE bulk author query"]

    S --> T[in_the_loop = true<br/>before_loop = false]
    L --> T
    T --> U["next_post() → setup_postdata()<br/>do_action('the_post')"]

    style F fill:#1565c0,color:#fff
    style Q fill:#2e7d32,color:#fff
    style S fill:#2e7d32,color:#fff
```
