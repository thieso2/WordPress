<?php
/**
 * Differential-testing bridge for the post + site block family.
 *
 * Reads a JSON array of cases on stdin and prints
 *   { "fixtures": { … }, "rendered": [ … ] }
 * where `fixtures` is the oracle's own corpus, projected onto the target schema, and
 * `rendered` is what WP_Block::render() produced for each case.
 *
 * Both halves come from the same running WordPress 7.2-alpha-63330, which is the point:
 * the spec never hand-writes an input OR an expectation. AD-08.
 */
$bootstrap = getenv('WP_ORACLE_BOOTSTRAP');
if (!$bootstrap || !file_exists($bootstrap)) { fwrite(STDERR, "oracle bootstrap not found\n"); exit(2); }
require $bootstrap;
global $wpdb;

$cases = json_decode(stream_get_contents(STDIN), true);

// ── Fixtures ────────────────────────────────────────────────────────────────────
$settings = array();
foreach (array('blogname','blogdescription','home','siteurl','date_format','time_format',
               'timezone_string','gmt_offset','avatar_default','avatar_rating','site_logo',
               'permalink_structure') as $name) {
    $value = get_option($name);
    if ($value !== false) { $settings[$name] = is_scalar($value) ? (string) $value : $value; }
}

$users = array();
foreach (get_users(array('number' => -1)) as $u) {
    $users[] = array('id' => (int) $u->ID, 'login' => $u->user_login, 'nicename' => $u->user_nicename,
                     'email' => $u->user_email, 'display_name' => $u->display_name,
                     'registered_at' => $u->user_registered);
}

$taxonomies = array();
$terms = array();
foreach (array('category', 'post_tag') as $taxonomy) {
    $taxonomies[] = $taxonomy;
    foreach (get_terms(array('taxonomy' => $taxonomy, 'hide_empty' => false)) as $t) {
        $terms[] = array('id' => (int) $t->term_id, 'taxonomy' => $taxonomy, 'name' => $t->name,
                         'slug' => $t->slug, 'description' => $t->description,
                         'parent' => (int) $t->parent, 'count' => (int) $t->count);
    }
}

$posts = array();
$assignments = array();
$rows = $wpdb->get_results("SELECT * FROM {$wpdb->posts} WHERE post_type IN ('post','page') ORDER BY ID");
foreach ($rows as $p) {
    $posts[] = array(
        'id' => (int) $p->ID, 'type' => $p->post_type, 'author' => (int) $p->post_author,
        'parent' => (int) $p->post_parent, 'title' => $p->post_title, 'name' => $p->post_name,
        'content' => $p->post_content, 'excerpt' => $p->post_excerpt, 'status' => $p->post_status,
        'date_gmt' => $p->post_date_gmt, 'modified_gmt' => $p->post_modified_gmt,
        'password' => $p->post_password, 'menu_order' => (int) $p->menu_order,
        'thumbnail' => (int) get_post_thumbnail_id($p->ID),
    );
    foreach (wp_get_object_terms($p->ID, array('category','post_tag')) as $t) {
        $assignments[] = array('post' => (int) $p->ID, 'term' => (int) $t->term_id);
    }
}

$assets = array();
foreach (get_posts(array('post_type' => 'attachment', 'numberposts' => -1, 'post_status' => 'inherit')) as $a) {
    $meta = wp_get_attachment_metadata($a->ID);
    $assets[] = array(
        'id' => (int) $a->ID, 'title' => $a->post_title, 'name' => $a->post_name,
        'mime_type' => $a->post_mime_type, 'uploader' => (int) $a->post_author,
        'parent' => (int) $a->post_parent,
        'alt' => (string) get_post_meta($a->ID, '_wp_attachment_image_alt', true),
        'caption' => $a->post_excerpt,
        'metadata' => is_array($meta) ? $meta : array(),
    );
}

$comments = array();
foreach (get_comments(array('status' => 'approve')) as $c) {
    $comments[] = array('id' => (int) $c->comment_ID, 'post' => (int) $c->comment_post_ID,
                        'parent' => (int) $c->comment_parent, 'user' => (int) $c->user_id,
                        'author_name' => $c->comment_author, 'author_email' => $c->comment_author_email,
                        'author_url' => $c->comment_author_url, 'content' => $c->comment_content,
                        'date_gmt' => $c->comment_date_gmt);
}

// ── Render ──────────────────────────────────────────────────────────────────────
$rendered = array();
foreach ($cases as $case) {
    $ctx = array();
    $qv = $case['query_vars'] ?? null;
    if ($qv !== null) {
        $q = new WP_Query();
        $q->query($qv);
        $GLOBALS['wp_query'] = $q;
        $GLOBALS['wp_the_query'] = $q;
        if ($q->have_posts()) { $q->the_post(); }
    } else {
        $GLOBALS['wp_query'] = new WP_Query();
        $GLOBALS['wp_the_query'] = $GLOBALS['wp_query'];
    }
    if (!empty($case['post_slug'])) {
        $id = $wpdb->get_var($wpdb->prepare(
            "SELECT ID FROM {$wpdb->posts} WHERE post_name = %s AND post_type IN ('post','page') ORDER BY ID LIMIT 1",
            $case['post_slug']
        ));
        if ($id) {
            $p = get_post($id);
            $GLOBALS['post'] = $p;
            setup_postdata($p);
            $ctx['postId'] = (int) $id;
            $ctx['postType'] = $p->post_type;
        }
    }
    if (!empty($case['context_term'])) {
        $t = get_term_by('slug', $case['context_term']['slug'], $case['context_term']['taxonomy']);
        if ($t) { $ctx['termId'] = (int) $t->term_id; $ctx['taxonomy'] = $case['context_term']['taxonomy']; }
    }
    foreach (($case['flags'] ?? array()) as $flag => $value) { $GLOBALS['wp_query']->$flag = (bool) $value; }
    foreach (($case['context'] ?? array()) as $k => $v) { $ctx[$k] = $v; }
    $parsed = parse_blocks($case['markup']);
    // render_block() (wp-includes/blocks.php) applies `render_block_data` to the ROOT
    // block before WP_Block is built; WP_Block::render() applies it only to INNER blocks
    // (class-wp-block.php:614). A page reaches every block through one of the two, so a
    // bare `new WP_Block(...)->render()` under-renders the case's root: no
    // `wp-elements-<n>` (elements.php:308) and no `is-style-<variation>--<n>`
    // (block-style-variations.php:265). Same arguments render_block() passes:
    // ($parsed_block, $source_block, $parent_block = null).
    $parsed_block = apply_filters('render_block_data', $parsed[0], $parsed[0], null);
    $block = new WP_Block($parsed_block, $ctx);
    $rendered[] = $block->render();
}

echo json_encode(array(
    'fixtures' => array('settings' => $settings, 'users' => $users, 'taxonomies' => $taxonomies,
                        'terms' => $terms, 'posts' => $posts, 'assignments' => $assignments,
                        'assets' => $assets, 'comments' => $comments),
    'rendered' => $rendered,
), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
