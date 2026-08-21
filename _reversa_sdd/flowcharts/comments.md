# Flowchart — `comments`

> 🟢 CONFIRMED — derived from `wp-includes/comment.php`

## Submission pipeline

```mermaid
flowchart TD
    A["POST to wp-comments-post.php"] --> B["wp_handle_comment_submission(POST)"]
    B --> C{post exists, comments open,<br/>not password-protected?}
    C -->|no| D[["WP_Error"]]
    C -->|yes| E["build commentdata<br/>preprocess_comment filter"]
    E --> F["wp_new_comment(commentdata)"]
    F --> G["wp_allow_comment(commentdata)"]

    G --> H["① duplicate check"]
    H --> I["② flood check"]
    I --> J["③ wp_check_comment_data()<br/>approval decision"]

    J --> K["wp_insert_comment()"]
    K --> L["do_action('comment_post',<br/>id, approved, commentdata)"]
    L --> M["wp_update_comment_count(post_id)"]
    M --> N[redirect back to the post]

    style D fill:#c62828,color:#fff
    style N fill:#2e7d32,color:#fff
```

## ① Duplicate detection

```mermaid
flowchart TD
    A["wp_allow_comment()"] --> B["SELECT comment_ID FROM wp_comments<br/>WHERE comment_post_ID = %d<br/>AND comment_parent = %s<br/>AND comment_approved != 'trash'<br/>AND ( comment_author = %s<br/>&nbsp;&nbsp;[AND comment_author_email = %s] )<br/>AND comment_content = %s<br/>LIMIT 1"]
    B --> C["apply_filters('duplicate_comment_id')"]
    C --> D{dupe_id found?}
    D -->|no| E[continue to flood check]
    D -->|yes| F["do_action('comment_duplicate_trigger')"]
    F --> G{context}
    G -->|"$wp_error"| H[["WP_Error comment_duplicate, 409"]]
    G -->|AJAX| I[["die(message)"]]
    G -->|normal| J[["wp_die(message, 409)"]]

    K["note: trashed comments are excluded,<br/>so resubmitting a trashed comment is allowed"]

    style H fill:#c62828,color:#fff
    style I fill:#c62828,color:#fff
    style J fill:#c62828,color:#fff
    style E fill:#2e7d32,color:#fff
```

## ② Flood control — a hook point, not a rate limit

```mermaid
flowchart TD
    A["do_action('check_comment_flood')<br/>apply_filters('wp_is_comment_flood', FALSE, …)"] --> B["core callback registered by<br/>check_comment_flood_db():<br/>wp_check_comment_flood()"]

    B --> C{"is_flood already true?"}
    C -->|yes| D[trust the earlier callback]
    C -->|no| E{"current_user_can('manage_options')<br/>OR 'moderate_comments'?"}
    E -->|yes| F[["return false —<br/>admins never throttled"]]
    E -->|no| G["hour_ago = now - HOUR_IN_SECONDS"]

    G --> H{logged in?}
    H -->|yes| I["check_column = user_id<br/>user = current_user_id()"]
    H -->|no| J["check_column = comment_author_IP<br/>user = ip"]

    I --> K
    J --> K["SELECT comment_date_gmt<br/>FROM wp_comments<br/>WHERE comment_date_gmt &gt;= hour_ago<br/>AND ( check_column = %s<br/>&nbsp;&nbsp;OR comment_author_email = %s )<br/>ORDER BY comment_date_gmt DESC<br/>LIMIT 1"]

    K --> L{a comment found<br/>within the hour?}
    L -->|no| M[return false]
    L -->|yes| N["flood_die = apply_filters(<br/>'comment_flood_filter',<br/>FALSE, last, new )"]

    N --> O{flood_die?}
    O -->|"false — THE DEFAULT"| M
    O -->|true| P["do_action('comment_flood_trigger')<br/>429 / die / return true"]

    Q[["CORE NEVER SETS flood_die TRUE.<br/>The query runs, the hook fires,<br/>and the answer is always 'not flooding'<br/>unless a plugin says otherwise."]]

    style F fill:#1565c0,color:#fff
    style M fill:#2e7d32,color:#fff
    style P fill:#c62828,color:#fff
    style Q fill:#ef6c00,color:#fff
```

## ③ Approval decision

```mermaid
flowchart TD
    A["wp_check_comment_data(comment_data)"] --> B{user_id set?}
    B -->|yes| C["user = get_userdata(user_id)<br/>post_author = SELECT post_author<br/>FROM wp_posts WHERE ID = %d"]
    B -->|no| D
    C --> E{"user_id === post_author<br/>OR user-&gt;has_cap('moderate_comments')?"}
    E -->|yes| F["approved = 1<br/>'The author and the admins<br/>get respect'<br/>NO moderation checks at all"]
    E -->|no| D["check_comment(author, email, url,<br/>content, ip, agent, type)"]

    D --> G{check_comment result}
    G -->|true| H[approved = 1]
    G -->|false| I[approved = 0 — held]

    H --> J
    I --> J["wp_check_comment_disallowed_list(<br/>author, email, url, content, ip, agent)"]
    J --> K{disallowed match?}
    K -->|no| L
    K -->|yes| M{"EMPTY_TRASH_DAYS truthy?"}
    M -->|yes| N["approved = 'trash'"]
    M -->|no| O["approved = 'spam'"]

    F --> L
    N --> L
    O --> L["apply_filters('pre_comment_approved',<br/>approved, comment_data)<br/><br/>a plugin can override<br/>the whole pipeline here"]
    L --> P[final status]

    style F fill:#1565c0,color:#fff
    style N fill:#ef6c00,color:#fff
    style O fill:#c62828,color:#fff
    style L fill:#7b1fa2,color:#fff
```

## `check_comment()` — the four moderation rules

```mermaid
flowchart TD
    A["check_comment(...)<br/>true = auto-approve<br/>false = hold"] --> B{"option comment_moderation === '1'?"}
    B -->|yes| C[["return FALSE — hold everything<br/>ALL other rules skipped"]]
    B -->|no| D["comment = apply_filters('comment_text', …)<br/>⚠️ moderation sees FILTERED text"]

    D --> E{option comment_max_links set?}
    E -->|yes| F["num_links = preg_match_all(<br/>'/&lt;a [^&gt;]*href/i', comment)<br/>apply_filters('comment_max_links_url')"]
    F --> G{"num_links &gt;= max_links?"}
    G -->|yes| C
    G -->|no| H
    E -->|no| H{option moderation_keys non-empty?}

    H -->|yes| I["for each keyword line:<br/>pattern = '#' . preg_quote(word) . '#iu'"]
    I --> J{"pattern matches ANY of:<br/>author · email · url<br/>content · user_ip · user_agent?"}
    J -->|yes| C
    J -->|no| K
    H -->|no| K{"option comment_previously_approved === '1'<br/>AND type not trackback/pingback<br/>AND author and email non-empty?"}

    K -->|no| L[["return TRUE — approve"]]
    K -->|yes| M{"registered user<br/>(get_user_by email)?"}
    M -->|yes| N["SELECT comment_approved<br/>WHERE user_id = %d<br/>AND comment_approved = '1'"]
    M -->|no| O["SELECT comment_approved<br/>WHERE comment_author = %s<br/>AND comment_author_email = %s<br/>AND comment_approved = '1'"]
    N --> P
    O --> P{prior approved<br/>comment exists?}
    P -->|yes| L
    P -->|no| C

    style C fill:#ef6c00,color:#fff
    style L fill:#2e7d32,color:#fff
    style D fill:#7b1fa2,color:#fff
```
