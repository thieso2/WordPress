# Flowchart — `block-editor`

> 🟢 CONFIRMED — derived from `wp-includes/class-wp-block-parser.php` and `wp-includes/blocks.php`

## The content format

```mermaid
flowchart TD
    A["post_content is VALID HTML<br/>with structure in comments"] --> B["&lt;!-- wp:paragraph --&gt;<br/>&lt;p&gt;Hello&lt;/p&gt;<br/>&lt;!-- /wp:paragraph --&gt;"]
    A --> C["&lt;!-- wp:spacer {\&quot;height\&quot;:\&quot;20px\&quot;} /--&gt;<br/>VOID — self-closing"]
    A --> D["plain text with no delimiter<br/>→ core/freeform"]

    E[["Consequence: an install with the<br/>block editor disabled still renders<br/>every post correctly."]]

    F["namespace optional:<br/>wp:paragraph ≡ core/paragraph"]

    style E fill:#2e7d32,color:#fff
```

## Parser stack machine

```mermaid
flowchart TD
    A["parse(document)"] --> B["proceed()"]
    B --> C["next_token() → type, name, attrs,<br/>start_offset, token_length"]
    C --> D["leading_html_start =<br/>start_offset &gt; offset ? offset : null<br/>← 'HTML soup before the next block'"]

    D --> E{token_type}

    E -->|"no-more-tokens"| F{stack depth}
    F -->|0| G["add_freeform()<br/>return false"]
    F -->|1| H["add_block_from_stack()<br/>IMPLICIT CLOSER<br/>return false"]
    F -->|"&gt; 1"| I["while stack:<br/>add_block_from_stack()<br/>close ALL implicitly"]

    E -->|"void-block"| J["emit immediately<br/>NO stack push"]
    E -->|"block-opener"| K["push onto stack"]
    E -->|"block-closer"| L["pop, attach to parent<br/>via add_inner_block()"]

    J --> M{more input?}
    K --> M
    L --> M
    M -->|yes| B
    M -->|no| N[return output tree]
    G --> N
    H --> N
    I --> N

    O[["THE PARSER CANNOT FAIL.<br/>Malformed input → freeform<br/>or implicit closure.<br/>No validation stage, no error signal."]]

    style H fill:#ef6c00,color:#fff
    style I fill:#ef6c00,color:#fff
    style O fill:#7b1fa2,color:#fff
    style N fill:#2e7d32,color:#fff
```

## Lossless round-tripping via `innerContent`

```mermaid
flowchart TD
    A["&lt;!-- wp:group --&gt;<br/>&lt;div class='wp-block-group'&gt;<br/>&nbsp;&nbsp;&lt;!-- wp:paragraph --&gt;&lt;p&gt;A&lt;/p&gt;&lt;!-- /wp:paragraph --&gt;<br/>&lt;/div&gt;<br/>&lt;!-- /wp:group --&gt;"] --> B[parse_blocks]

    B --> C["blockName: 'core/group'<br/>innerBlocks: [ paragraph block ]<br/>innerContent: [<br/>&nbsp;&nbsp;'&lt;div class=…&gt;',   ← STRING = my own HTML<br/>&nbsp;&nbsp;null,                ← NULL = a child goes here<br/>&nbsp;&nbsp;'&lt;/div&gt;'            ← STRING<br/>]"]

    C --> D["serialize_block(block)"]
    D --> E["index = 0<br/>for chunk in innerContent:"]
    E --> F{"is_string(chunk)?"}
    F -->|yes| G["append the literal HTML"]
    F -->|"no — null"| H["append serialize_block(<br/>innerBlocks[index++] )"]
    G --> I
    H --> I{more chunks?}
    I -->|yes| E
    I -->|no| J["get_comment_delimited_block_content(<br/>blockName, attrs, content )"]
    J --> K[identical to the input]

    L[["Separating 'my HTML' (strings) from<br/>'my children's positions' (nulls) is what<br/>makes parse → serialize lossless."]]

    style L fill:#1565c0,color:#fff
    style K fill:#2e7d32,color:#fff
```

## Block registration — three metadata sources

```mermaid
flowchart TD
    A["register_block_type_from_metadata(<br/>file_or_folder, args)"] --> B["normalize path;<br/>metadata_file = folder/block.json"]
    B --> C{"path starts with<br/>ABSPATH . WPINC?"}
    C -->|yes| D["is_core_block = true<br/>metadata_file_exists assumed TRUE<br/>← skips file_exists() for 115 blocks"]
    C -->|no| E["metadata_file_exists =<br/>file_exists(metadata_file)"]

    D --> F
    E --> F["① WP_Block_Metadata_Registry::get_metadata()<br/>pre-built manifest (blocks-json.php)"]
    F --> G{found?}
    G -->|yes| H[use manifest metadata]
    G -->|no| I{metadata_file_exists?}
    I -->|yes| J["② wp_json_file_decode(block.json)"]
    I -->|no| K["③ metadata = []"]

    H --> L
    J --> L
    K --> L{"is_array AND<br/>(metadata name OR args name)?"}
    L -->|no| M[["return FALSE"]]
    L -->|yes| N["apply_filters('block_type_metadata')"]

    N --> O{"name starts with 'core/'?"}
    O -->|yes| P["implicit handles:<br/>style ← wp-block-{name}<br/>editorStyle ← wp-block-{name}-editor<br/>+ wp-block-{name}-theme when<br/>&nbsp;&nbsp;wp-block-styles is supported"]
    O -->|no| Q
    P --> Q["property_mappings:<br/>apiVersion→api_version<br/>providesContext→provides_context<br/>usesContext→uses_context …"]
    Q --> R["new WP_Block_Type(...)<br/>register in WP_Block_Type_Registry"]

    style D fill:#1565c0,color:#fff
    style M fill:#c62828,color:#fff
    style R fill:#2e7d32,color:#fff
```

## Rendering — static vs dynamic

```mermaid
flowchart TD
    A["the_content filter → do_blocks(content)"] --> B["parse_blocks(content)"]
    B --> C[for each parsed block]
    C --> D["render_block(parsed_block)"]
    D --> E["apply_filters('pre_render_block')"]
    E --> F{"non-null?"}
    F -->|yes| G[["short-circuit —<br/>use the filter's output"]]
    F -->|no| H{"block type has<br/>render_callback?"}

    H -->|"NO — static"| I["return the saved innerHTML<br/>content came from the database"]
    H -->|"YES — dynamic"| J["call render_callback(<br/>attributes, content, WP_Block )<br/><br/>output computed NOW"]

    I --> K["apply_filters('render_block')"]
    J --> K
    K --> L[concatenated output]

    M[["~94 of 115 core blocks are dynamic.<br/>Two installs with identical post_content<br/>can render differently."]]

    style G fill:#1565c0,color:#fff
    style J fill:#ef6c00,color:#fff
    style M fill:#7b1fa2,color:#fff
```
