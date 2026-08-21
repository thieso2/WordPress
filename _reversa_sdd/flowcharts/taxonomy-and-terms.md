# Flowchart — `taxonomy-and-terms`

> 🟢 CONFIRMED — derived from `wp-includes/taxonomy.php`

## The three-table model

```mermaid
erDiagram
    wp_terms ||--o{ wp_term_taxonomy : "one word, many classifications"
    wp_term_taxonomy ||--o{ wp_term_relationships : "assignments use tt_id"
    wp_term_taxonomy ||--o{ wp_term_taxonomy : "parent (no FK, cycles possible)"
    wp_posts ||--o{ wp_term_relationships : object_id
    wp_termmeta }o--|| wp_terms : term_id

    wp_terms {
        bigint term_id PK
        varchar name "the WORD — 'News'"
        varchar slug
        bigint term_group "alias_of synonym grouping"
    }
    wp_term_taxonomy {
        bigint term_taxonomy_id PK "THE id that links to objects"
        bigint term_id FK
        varchar taxonomy "the CLASSIFICATION — 'category'"
        longtext description
        bigint parent "hierarchy, no referential integrity"
        bigint count "DIRECT assignments only"
    }
    wp_term_relationships {
        bigint object_id FK "the ASSIGNMENT"
        bigint term_taxonomy_id FK
        int term_order
    }
```

**The trap:** most API functions accept `term_id`, but `wp_term_relationships` stores
`term_taxonomy_id`. One `term_id` used as both a category and a tag has two different `tt_id`s.

## `wp_insert_term()` — insert first, detect duplicate after

```mermaid
flowchart TD
    A["wp_insert_term(term, taxonomy, args)"] --> B{taxonomy_exists?}
    B -->|no| C[["WP_Error invalid_taxonomy"]]
    B -->|yes| D["pre_insert_term filter"]
    D --> E{is_wp_error?}
    E -->|yes| F[["return the error"]]
    E -->|no| G{"is_int(term) AND term === 0?"}
    G -->|yes| H[["WP_Error invalid_term_id"]]
    G -->|no| I{"trim(term) === ''?"}
    I -->|yes| J[["WP_Error empty_term_name"]]
    I -->|no| K{"parent &gt; 0 AND<br/>!term_exists(parent)?"}
    K -->|yes| L[["WP_Error missing_parent"]]
    K -->|no| M["description = (string) description<br/>← null would be a DB error"]

    M --> N["sanitize_term(args, taxonomy, 'db')<br/>name = wp_unslash(name)"]
    N --> O{"name === '' AFTER sanitize?"}
    O -->|yes| P[["WP_Error invalid_term_name<br/>— checked a SECOND time"]]
    O -->|no| Q["slug = provided ?: sanitize_title(name)"]

    Q --> R{alias_of set?}
    R -->|yes| S["target has term_group?<br/>yes → join it<br/>no → MAX(term_group)+1<br/>and move target into it"]
    R -->|no| T
    S --> T["INSERT INTO wp_terms<br/>term_id = insert_id"]

    T --> U["SELECT tt.term_taxonomy_id<br/>WHERE tt.taxonomy = %s<br/>AND t.term_id = %d"]
    U --> V{found?}
    V -->|yes| W[["term already in this taxonomy<br/>return existing ids"]]
    V -->|no| X["INSERT INTO wp_term_taxonomy<br/>tt_id = insert_id"]

    X --> Y["SELECT ... WHERE t.slug = %s<br/>AND tt.parent = %d<br/>AND tt.taxonomy = %s<br/>AND t.term_id &lt; %d  ← OLDER ONLY<br/>AND tt.term_taxonomy_id != %d"]
    Y --> Z["wp_insert_term_duplicate_term_check filter"]
    Z --> AA{duplicate found?}

    AA -->|yes| AB[["DELETE the rows just inserted<br/>return the pre-existing term_id / tt_id<br/><br/>last writer LOSES —<br/>concurrent identical inserts converge"]]
    AA -->|no| AC["do_action('create_term')<br/>do_action('created_term')"]
    AC --> AD["return {term_id, term_taxonomy_id}"]

    style C fill:#c62828,color:#fff
    style H fill:#c62828,color:#fff
    style J fill:#c62828,color:#fff
    style L fill:#c62828,color:#fff
    style P fill:#c62828,color:#fff
    style AB fill:#7b1fa2,color:#fff
    style AD fill:#2e7d32,color:#fff
```

## `wp_set_object_terms()` — string creates, integer skips

```mermaid
flowchart TD
    A["wp_set_object_terms(object_id, terms, taxonomy, append)"] --> B{taxonomy_exists?}
    B -->|no| C[["WP_Error"]]
    B -->|yes| D[normalize terms to array]
    D --> E{append?}
    E -->|no| F["old_tt_ids = wp_get_object_terms(<br/>fields =&gt; tt_ids)"]
    E -->|yes| G["old_tt_ids = []"]
    F --> H
    G --> H[for each term]

    H --> I{"trim(term) === ''?"}
    I -->|yes| J[skip]
    I -->|no| K["term_info = term_exists(term, taxonomy)"]
    K --> L{found?}
    L -->|yes| M[use it]
    L -->|no| N{"is_int(term)?"}

    N -->|"YES — integer"| O[["SILENTLY SKIPPED<br/>no error, no signal"]]
    N -->|"NO — string"| P["wp_insert_term(term, taxonomy)<br/>CREATES THE TERM"]

    P --> Q{is_wp_error?}
    Q -->|yes| C
    Q -->|no| M
    M --> R["tt_id = term_info['term_taxonomy_id']"]
    R --> S["SELECT term_taxonomy_id<br/>FROM wp_term_relationships<br/>WHERE object_id AND tt_id<br/><br/>⚠️ ONE QUERY PER TERM"]
    S --> T{already related?}
    T -->|yes| U[skip — no-op]
    T -->|no| V["do_action add_term_relationship<br/>INSERT relationship<br/>do_action added_term_relationship<br/>new_tt_ids[] = tt_id"]

    V --> W{more terms?}
    U --> W
    O --> W
    J --> W
    W -->|yes| H
    W -->|no| X{new_tt_ids non-empty?}
    X -->|yes| Y["wp_update_term_count(new_tt_ids, taxonomy)"]
    X -->|no| Z
    Y --> Z{append == false?}
    Z -->|yes| AA["DELETE relationships in old_tt_ids<br/>but not in tt_ids"]
    Z -->|no| AB[done]
    AA --> AB

    style O fill:#c62828,color:#fff
    style P fill:#ef6c00,color:#fff
    style S fill:#ef6c00,color:#fff
    style AB fill:#2e7d32,color:#fff
```

## Deferred term counting

```mermaid
flowchart TD
    A["wp_update_term_count(terms, taxonomy, do_deferred)"] --> B["static $_deferred"]
    B --> C{do_deferred?}
    C -->|yes| D["for each queued taxonomy:<br/>wp_update_term_count_now()<br/>then unset the queue"]
    C -->|no| E
    D --> E{terms empty?}
    E -->|yes| F[return false]
    E -->|no| G{"wp_defer_term_counting()?"}

    G -->|yes| H["_deferred[taxonomy] = array_unique(<br/>merge(existing, terms))<br/>return true<br/><br/>bulk import: thousands of<br/>recalcs collapse into one pass"]
    G -->|no| I["wp_update_term_count_now(terms, taxonomy)"]

    I --> J{"taxonomy-&gt;update_count_callback set?"}
    J -->|yes| K["call_user_func(callback, terms, taxonomy)<br/>← how post_tag and attachments<br/>count differently"]
    J -->|no| L["default COUNT query over<br/>term_relationships x posts"]

    style H fill:#1565c0,color:#fff
    style K fill:#7b1fa2,color:#fff
```

## `_pad_term_counts()` — hierarchical rollup at read time

```mermaid
flowchart TD
    A["_pad_term_counts(&amp;terms, taxonomy)"] --> B{is_taxonomy_hierarchical?}
    B -->|no| C[["return — flat taxonomies<br/>use the stored count"]]
    B -->|yes| D["_get_term_hierarchy(taxonomy)"]
    D --> E{empty?}
    E -->|yes| C
    E -->|no| F["build terms_by_id and<br/>term_ids[tt_id] =&gt; term_id"]

    F --> G["ONE QUERY:<br/>SELECT object_id, term_taxonomy_id<br/>FROM term_relationships<br/>INNER JOIN posts ON object_id = ID<br/>WHERE tt_id IN (...)<br/>AND post_type IN (object types)<br/>AND post_status = 'publish'<br/><br/>⚠️ PUBLISHED ONLY — drafts<br/>never increment a count"]

    G --> H["term_items[term_id][object_id] = touches<br/><br/>keyed by OBJECT ID, not a running sum"]
    H --> I[for each term_id: walk up parents]

    I --> J{"terms_by_id[child] exists<br/>AND has a parent?"}
    J -->|no| K[stop this chain]
    J -->|yes| L["ancestors[] = child<br/>copy every object_id from<br/>term_items[term_id] into<br/>term_items[parent]"]
    L --> M["child = parent"]
    M --> N{"parent already in ancestors?"}
    N -->|"YES — CYCLE"| O[["break<br/><br/>guard against a corrupted<br/>parent chain; no FK exists<br/>to prevent one"]]
    N -->|no| J

    K --> P
    O --> P["transfer count(items) onto<br/>each term object BY REFERENCE<br/><br/>dedup by object id ⇒ a post in<br/>both child and parent counts ONCE"]

    style C fill:#616161,color:#fff
    style G fill:#ef6c00,color:#fff
    style O fill:#c62828,color:#fff
    style P fill:#2e7d32,color:#fff
```
