<?php
/**
 * Oracle corpus seeder — Wave 0.
 *
 * handoff.md: "Build it first. Seed it properly: all 16 post types, hierarchical and
 * flat taxonomies, threaded comments, every role, drafts carrying 0000-00-00 00:00:00,
 * serialized postmeta/options, 4-byte UTF-8, quote- and backslash-heavy text."
 *
 * Idempotent by construction: run `php tools/reset.php` first for a clean corpus.
 * Deterministic: no randomness, fixed dates, so the corpus round-trips identically.
 */
require_once __DIR__ . '/_bootstrap.php';
require_once __DIR__ . '/corpus.php';

// ⚠️ The corpus must be STABLE. Golden files are byte-compared, so a corpus that drifts
// between runs turns every capture into a false divergence -- and this seeder is
// additive by nature: wp_insert_post() with a colliding title allocates a `-2` slug
// rather than refusing, and the raw zero-date INSERTs have nothing to collide with at
// all. Re-seeding therefore means resetting first.
global $wpdb;
$already = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_name LIKE 'zero-date%' OR post_title LIKE 'Auto draft%'" );
if ( $already > 0 && ! in_array( '--force', (array) ( $argv ?? array() ), true ) ) {
    fwrite( STDERR, "This oracle is already seeded ({$already} marker rows).\n" );
    fwrite( STDERR, "Re-seeding would DRIFT the corpus and invalidate every golden file.\n" );
    fwrite( STDERR, "Reset first:  php tools/reset.php && php tools/install.php && php tools/seed.php\n" );
    fwrite( STDERR, "Or:           bin/oracle reseed\n" );
    exit( 1 );
}

global $wpdb;
$report = array();
function note( $k, $v ) { global $report; $report[ $k ] = $v; echo str_pad( $k, 34 ) . $v . "\n"; }

// WordPress functions expect SLASHED input (wp_magic_quotes at request time, DR-02).
// Driving them from CLI means we must slash by hand, or every backslash is eaten.
function s( $v ) { return wp_slash( $v ); }

$FIXED = '2026-03-15 10:00:00';

// ── 1. Every role, one user each ───────────────────────────────────────────────
$users = array();
foreach ( array( 'administrator', 'editor', 'author', 'contributor', 'subscriber' ) as $role ) {
    $login = 'oracle_' . $role;
    $id    = username_exists( $login );
    if ( ! $id ) {
        $id = wp_insert_user( array(
            'user_login'   => $login,
            'user_pass'    => 'pw-' . $role,
            'user_email'   => $login . '@example.com',
            'display_name' => s( ucfirst( $role ) . " O'Brien \"the tester\" 😀" ),
            'first_name'   => s( "Ünïcødé" ),
            'description'  => s( CORPUS_QUOTES ),
            'role'         => $role,
            'user_url'     => 'https://example.com/~' . $role,
        ) );
    }
    $users[ $role ] = $id;
    // usermeta with a serialized payload (T-03 exercises the role map itself).
    update_user_meta( $id, 'oracle_serialized', corpus_serialized_array() );
    update_user_meta( $id, 'oracle_backslash', s( CORPUS_BACKSLASH ) );
}
$users['admin'] = 1;
note( 'users', count( $users ) );

// ── 2. Taxonomies: hierarchical 3 deep + flat ─────────────────────────────────
$cat_top = wp_insert_term( s( "Top « Category » 😀" ), 'category', array( 'slug' => 'top-category', 'description' => s( CORPUS_QUOTES ) ) );
$cat_top = is_wp_error( $cat_top ) ? get_term_by( 'slug', 'top-category', 'category' )->term_id : $cat_top['term_id'];
$cat_mid = wp_insert_term( s( 'Middle Category' ), 'category', array( 'slug' => 'middle-category', 'parent' => $cat_top ) );
$cat_mid = is_wp_error( $cat_mid ) ? get_term_by( 'slug', 'middle-category', 'category' )->term_id : $cat_mid['term_id'];
$cat_leaf = wp_insert_term( s( 'Leaf Category' ), 'category', array( 'slug' => 'leaf-category', 'parent' => $cat_mid ) );
$cat_leaf = is_wp_error( $cat_leaf ) ? get_term_by( 'slug', 'leaf-category', 'category' )->term_id : $cat_leaf['term_id'];
// Same slug under a DIFFERENT parent — legal in the legacy, and the case F-DD-05 says
// the legacy's own UNIQUE KEY (term_id, taxonomy) misses entirely.
wp_insert_term( s( 'Leaf Category' ), 'category', array( 'slug' => 'leaf-category-2', 'parent' => $cat_top ) );

$tags = array();
foreach ( array( 'flat-tag-one', 'flat-tag-two', 'tag-with-😀-emoji', "tag-with-quote" ) as $i => $slug ) {
    $t = wp_insert_term( s( 'Tag ' . $i . ' ' . CORPUS_ASTRAL ), 'post_tag', array( 'slug' => $slug ) );
    if ( ! is_wp_error( $t ) ) { $tags[] = $t['term_id']; }
}
foreach ( array_merge( array( $cat_top, $cat_mid, $cat_leaf ), $tags ) as $tid ) {
    update_term_meta( $tid, 'oracle_serialized', corpus_serialized_array() );
}
note( 'terms', $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->terms}" ) );

// ── 3. Articles: every status, plus the awkward ones ──────────────────────────
$post_ids = array();
foreach ( corpus_articles() as $i => $a ) {
    $args = array(
        'post_title'   => s( $a['title'] ),
        'post_content' => s( isset( $a['content'] ) ? $a['content'] : "Body $i\n\n" . CORPUS_ASTRAL . "\n\n" . CORPUS_BACKSLASH . "\n\n" . CORPUS_QUOTES ),
        'post_excerpt' => s( 'Excerpt ' . $i . ' — ' . CORPUS_QUOTES ),
        'post_status'  => $a['status'],
        'post_author'  => $users['author'],
        'post_type'    => 'post',
        'post_date'    => $FIXED,
    );
    if ( 'future' === $a['status'] ) { $args['post_date'] = gmdate( 'Y-m-d H:i:s', time() + 86400 ); }
    if ( isset( $a['password'] ) )   { $args['post_password'] = $a['password']; }
    $pid = wp_insert_post( $args, true );
    if ( is_wp_error( $pid ) ) { echo "  !! {$a['title']}: " . $pid->get_error_message() . "\n"; continue; }
    $post_ids[] = $pid;
    if ( ! empty( $a['sticky'] ) ) { stick_post( $pid ); }
    wp_set_post_terms( $pid, array( $cat_leaf ), 'category' );
    wp_set_post_terms( $pid, $tags, 'post_tag' );
    // Serialized postmeta + the residual bucket AD-03 keeps as key-value.
    update_post_meta( $pid, 'oracle_serialized', corpus_serialized_array() );
    update_post_meta( $pid, 'oracle_backslash', s( CORPUS_BACKSLASH ) );
    update_post_meta( $pid, 'oracle_astral', s( CORPUS_ASTRAL ) );
    add_post_meta( $pid, 'oracle_multi', 'value-a' );  // multi-valued: NOT unique
    add_post_meta( $pid, 'oracle_multi', 'value-b' );
}
note( 'posts (type=post)', count( $post_ids ) );

// ── 4. Drafts carrying 0000-00-00 00:00:00 — RISK-007, forced past wp_insert_post ─
// wp_insert_post normalises the date, so the zero date is written directly. That is
// exactly how the legacy stores an auto-draft, and it is what T-01 must map to NULL.
$zero_ids = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $wpdb->query( $wpdb->prepare(
        "INSERT INTO {$wpdb->posts}
         (post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
          post_status, comment_status, ping_status, post_name, post_modified, post_modified_gmt,
          post_parent, guid, post_type, to_ping, pinged, post_content_filtered)
         VALUES (%d, '0000-00-00 00:00:00', '0000-00-00 00:00:00', %s, %s, '',
                 'auto-draft', 'open', 'open', '', '0000-00-00 00:00:00', '0000-00-00 00:00:00',
                 0, '', 'post', '', '', '')",
        $users['author'], 'Zero-date body ' . $i, 'Auto draft ' . $i
    ) );
    $zero_ids[] = $wpdb->insert_id;
}
note( 'zero-date auto-drafts', count( $zero_ids ) );

// ── 5. Pages: a 3-level hierarchy + a page template + menu_order ──────────────
$page_top = wp_insert_post( array( 'post_title' => s( 'Parent Page' ), 'post_name' => 'parent-page', 'post_type' => 'page', 'post_status' => 'publish', 'post_content' => s( CORPUS_QUOTES ), 'post_author' => $users['editor'], 'menu_order' => 1 ) );
$page_mid = wp_insert_post( array( 'post_title' => s( 'Child Page' ), 'post_name' => 'child-page', 'post_type' => 'page', 'post_status' => 'publish', 'post_parent' => $page_top, 'post_author' => $users['editor'], 'menu_order' => 2 ) );
$page_leaf = wp_insert_post( array( 'post_title' => s( 'Grandchild Page' ), 'post_name' => 'grandchild-page', 'post_type' => 'page', 'post_status' => 'publish', 'post_parent' => $page_mid, 'post_author' => $users['editor'], 'menu_order' => 3 ) );
// Same slug, different parent: legal for hierarchical types (BR-MIGRATE-033).
wp_insert_post( array( 'post_title' => s( 'Child Page' ), 'post_name' => 'child-page', 'post_type' => 'page', 'post_status' => 'publish', 'post_parent' => $page_leaf, 'post_author' => $users['editor'] ) );
update_post_meta( $page_top, '_wp_page_template', 'templates/full-width.php' );
note( 'pages', $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type='page'" ) );

// ── 6. Threaded comments: 4 levels deep, every status ─────────────────────────
$target = $post_ids[0];
$mk = function ( $parent, $status, $label, $author_id = 0 ) use ( $target, $FIXED ) {
    return wp_insert_comment( array(
        'comment_post_ID'      => $target,
        'comment_parent'       => $parent,
        'comment_author'       => s( "Commenter \"$label\" O'Brien 😀" ),
        'comment_author_email' => 'commenter-' . sanitize_key( $label ) . '@example.com',
        'comment_author_url'   => 'https://example.com/' . sanitize_key( $label ),
        'comment_author_IP'    => '203.0.113.' . ( $parent % 250 + 1 ),
        'comment_content'      => s( "Comment $label\n" . CORPUS_QUOTES . "\n" . CORPUS_BACKSLASH . "\n" . CORPUS_ASTRAL ),
        'comment_approved'     => $status,
        'comment_date'         => $FIXED,
        'comment_date_gmt'     => $FIXED,
        'user_id'              => $author_id,
        'comment_agent'        => 'OracleSeeder/1.0',
    ) );
};
$c1 = $mk( 0,  '1', 'root-approved', $users['subscriber'] );
$c2 = $mk( $c1, '1', 'depth-2' );
$c3 = $mk( $c2, '1', 'depth-3' );
$c4 = $mk( $c3, '1', 'depth-4' );
$mk( 0, '0',      'pending' );
$mk( 0, 'spam',   'spam' );
$mk( 0, 'trash',  'trashed' );
$mk( 0, '1',      'second-root' );
foreach ( array( $c1, $c2 ) as $cid ) { update_comment_meta( $cid, 'oracle_serialized', corpus_serialized_array() ); }
// A pingback and a trackback: comment_type is not always 'comment' (BR-CMT family).
wp_insert_comment( array( 'comment_post_ID' => $target, 'comment_type' => 'pingback', 'comment_author' => 'Pingback Source', 'comment_content' => s( 'A pingback body' ), 'comment_approved' => '1', 'comment_date' => $FIXED, 'comment_date_gmt' => $FIXED ) );
wp_insert_comment( array( 'comment_post_ID' => $target, 'comment_type' => 'trackback', 'comment_author' => 'Trackback Source', 'comment_content' => s( 'A trackback body' ), 'comment_approved' => '1', 'comment_date' => $FIXED, 'comment_date_gmt' => $FIXED ) );
wp_update_comment_count( $target );
note( 'comments', $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->comments}" ) );

// ── 7. Attachments + serialized _wp_attachment_metadata (the AGG-Asset source) ─
$upload_dir = wp_upload_dir();
wp_mkdir_p( $upload_dir['path'] );
$att_ids = array();
foreach ( array(
    array( 'oracle-image.png',  'image/png',       1600, 1200 ),
    array( 'oracle-photo.jpeg', 'image/jpeg',      3000, 2000 ),
    array( 'oracle-doc.pdf',    'application/pdf', null, null ),
) as $f ) {
    list( $name, $mime, $w, $h ) = $f;
    $path = $upload_dir['path'] . '/' . $name;
    if ( ! file_exists( $path ) ) {
        // A real 1x1 PNG for the image cases so mime sniffing has something to read.
        file_put_contents( $path, base64_decode( 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' ) );
    }
    $aid = wp_insert_attachment( array(
        'post_title'     => s( "Asset \"$name\" 😀" ),
        'post_mime_type' => $mime,
        'post_status'    => 'inherit',
        'post_parent'    => $target,
        'post_excerpt'   => s( 'Caption with ' . CORPUS_QUOTES ),
        'post_content'   => s( 'Description ' . CORPUS_BACKSLASH ),
        'post_author'    => $users['author'],
    ), $path, $target );
    $att_ids[] = $aid;
    // ⚠️ The declared sizes must EXIST on disk. Earlier the seeder recorded
    // `_wp_attachment_metadata['sizes']` without writing the files, so every srcset the
    // oracle rendered pointed at a 404 — in both systems equally, which is why no parity
    // check caught it. A corpus that describes files it does not have is not a corpus.
    if ( $w ) {
        foreach ( array( 'thumb-', 'med-', 'large-' ) as $prefix ) {
            $variant = $upload_dir['path'] . '/' . $prefix . $name;
            if ( ! file_exists( $variant ) ) { copy( $path, $variant ); }
        }
    }
    $meta = array(
        'width' => $w, 'height' => $h, 'file' => ltrim( str_replace( $upload_dir['basedir'], '', $path ), '/' ),
        'sizes' => $w ? array(
            'thumbnail' => array( 'file' => 'thumb-' . $name, 'width' => 150, 'height' => 150, 'mime-type' => $mime ),
            'medium'    => array( 'file' => 'med-' . $name,   'width' => 300, 'height' => 225, 'mime-type' => $mime ),
            'large'     => array( 'file' => 'large-' . $name, 'width' => 1024,'height' => 768, 'mime-type' => $mime ),
        ) : array(),
        'image_meta' => array( 'aperture' => '2.8', 'credit' => s( "O'Brien \"Photo\"" ), 'camera' => 'Oracle', 'caption' => s( CORPUS_ASTRAL ), 'keywords' => array( 'a', 'b' ) ),
    );
    wp_update_attachment_metadata( $aid, $meta );
    update_post_meta( $aid, '_wp_attachment_image_alt', s( 'Alt text with "quotes" and 😀' ) );
}
// _thumbnail_id: the postmeta AD-03 promotes to a real FK.
set_post_thumbnail( $target, $att_ids[0] );
note( 'attachments', count( $att_ids ) );

// ── 8. Revisions + autosave ───────────────────────────────────────────────────
foreach ( array_slice( $post_ids, 0, 3 ) as $pid ) {
    for ( $r = 1; $r <= 3; $r++ ) {
        wp_update_post( array( 'ID' => $pid, 'post_content' => s( "Revision $r body " . CORPUS_ASTRAL ) ) );
        wp_save_post_revision( $pid );
    }
}
note( 'revisions', $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type='revision'" ) );

// ── 9. Nav menu + items: the nine _menu_item_* postmeta keys (BR-MENU-02) ─────
$menu_id = wp_create_nav_menu( 'Oracle Primary Menu' );
if ( is_wp_error( $menu_id ) ) { $menu_id = get_term_by( 'name', 'Oracle Primary Menu', 'nav_menu' )->term_id; }
$mi_home = wp_update_nav_menu_item( $menu_id, 0, array(
    'menu-item-title'  => s( 'Home "quoted"' ), 'menu-item-url' => home_url( '/' ),
    'menu-item-type'   => 'custom', 'menu-item-status' => 'publish',
    'menu-item-classes' => 'nav-home featured', 'menu-item-xfn' => 'me',
    'menu-item-attr-title' => s( "Title attribute with 'quotes'" ),
) );
$mi_page = wp_update_nav_menu_item( $menu_id, 0, array(
    'menu-item-title' => s( 'Parent Page' ), 'menu-item-object' => 'page',
    'menu-item-object-id' => $page_top, 'menu-item-type' => 'post_type',
    'menu-item-status' => 'publish', 'menu-item-parent-id' => $mi_home,
) );
wp_update_nav_menu_item( $menu_id, 0, array(
    'menu-item-title' => s( 'Leaf Category' ), 'menu-item-object' => 'category',
    'menu-item-object-id' => $cat_leaf, 'menu-item-type' => 'taxonomy',
    'menu-item-status' => 'publish', 'menu-item-parent-id' => $mi_page,
) );
set_theme_mod( 'nav_menu_locations', array( 'primary' => $menu_id ) );
note( 'nav_menu_items', $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type='nav_menu_item'" ) );

// ── 10. The remaining machinery post types — AD-02 splits every one of these ──
$machinery = array(
    'wp_block' => array( 'title' => s( 'Reusable Pattern' ), 'name' => 'reusable-pattern',
        'content' => s( '<!-- wp:paragraph --><p>' . CORPUS_QUOTES . '</p><!-- /wp:paragraph -->' ), 'status' => 'publish' ),
    'wp_template' => array( 'title' => s( 'Single Template' ), 'name' => 'single',
        'content' => s( '<!-- wp:template-part {"slug":"header"} /-->' ), 'status' => 'publish' ),
    'wp_template_part' => array( 'title' => s( 'Header Part' ), 'name' => 'header',
        'content' => s( '<!-- wp:site-title /-->' ), 'status' => 'publish' ),
    'wp_global_styles' => array( 'title' => s( 'Custom Styles' ), 'name' => 'wp-global-styles-oracle',
        'content' => wp_json_encode( array( 'version' => 3, 'styles' => array( 'color' => array( 'background' => '#ffffff' ) ), 'settings' => array( 'color' => array( 'palette' => array( array( 'slug' => 'primary', 'color' => '#0073aa', 'name' => 'Primary' ) ) ) ) ) ), 'status' => 'publish' ),
    'wp_navigation' => array( 'title' => s( 'Block Navigation' ), 'name' => 'block-navigation',
        'content' => s( '<!-- wp:navigation-link {"label":"Home"} /-->' ), 'status' => 'publish' ),
    'wp_font_family' => array( 'title' => s( 'Oracle Sans' ), 'name' => 'oracle-sans',
        'content' => wp_json_encode( array( 'fontFamily' => 'Oracle Sans, sans-serif', 'slug' => 'oracle-sans' ) ), 'status' => 'publish' ),
    'wp_font_face' => array( 'title' => s( 'Oracle Sans Regular' ), 'name' => 'oracle-sans-400',
        'content' => wp_json_encode( array( 'fontFamily' => 'Oracle Sans', 'fontWeight' => '400', 'fontStyle' => 'normal' ) ), 'status' => 'publish' ),
    'custom_css' => array( 'title' => s( 'twentytwentyfive' ), 'name' => 'twentytwentyfive',
        'content' => s( "body { color: #333; }\n/* quote \" and backslash \\ */" ), 'status' => 'publish' ),
    'customize_changeset' => array( 'title' => s( 'Changeset' ), 'name' => 'a1b2c3d4-0000-0000-0000-000000000001',
        'content' => wp_json_encode( array( 'blogname' => array( 'value' => 'Changed Title' ) ) ), 'status' => 'draft' ),
    'oembed_cache' => array( 'title' => s( 'oEmbed cache entry' ), 'name' => md5( 'https://example.com/video' ),
        'content' => wp_json_encode( array( 'html' => '<iframe src="https://example.com/e"></iframe>', 'type' => 'video' ) ), 'status' => 'publish' ),
    'user_request' => array( 'title' => s( 'export_personal_data' ), 'name' => 'export_personal_data',
        'content' => '', 'status' => 'request-pending' ),
);
$made = 0;
foreach ( $machinery as $ptype => $m ) {
    $args = array( 'post_type' => $ptype, 'post_title' => $m['title'], 'post_name' => $m['name'],
                   'post_content' => $m['content'], 'post_status' => $m['status'], 'post_author' => 1,
                   'post_date' => $FIXED );
    if ( 'user_request' === $ptype ) { $args['post_status'] = 'request-pending'; }
    $id = wp_insert_post( $args, true );
    if ( is_wp_error( $id ) ) {
        // Some machinery types reject wp_insert_post's status validation; write directly.
        $wpdb->insert( $wpdb->posts, array(
            'post_author' => 1, 'post_date' => $FIXED, 'post_date_gmt' => $FIXED,
            'post_content' => $m['content'], 'post_title' => $m['title'], 'post_excerpt' => '',
            'post_status' => $m['status'], 'comment_status' => 'closed', 'ping_status' => 'closed',
            'post_name' => $m['name'], 'post_modified' => $FIXED, 'post_modified_gmt' => $FIXED,
            'post_parent' => 0, 'guid' => home_url( '/?p=' . $ptype ), 'post_type' => $ptype,
            'to_ping' => '', 'pinged' => '', 'post_content_filtered' => '',
        ) );
        $id = $wpdb->insert_id;
    }
    if ( $id ) { $made++; }
    // user_request carries its subject in meta; oembed_cache carries a TTL.
    if ( 'user_request' === $ptype ) { update_post_meta( $id, '_user_email', 'subject@example.com' ); update_post_meta( $id, '_request_confirmed_timestamp', time() ); }
    if ( 'oembed_cache' === $ptype ) { update_post_meta( $id, '_oembed_time_' . md5( 'x' ), time() ); }
}
note( 'machinery post types seeded', $made );

// ── 11. Options: serialized, autoload on and off, and the 150 KB threshold ────
update_option( 'oracle_serialized_option', corpus_serialized_array(), true );
update_option( 'oracle_backslash_option', CORPUS_BACKSLASH, true );
update_option( 'oracle_astral_option', CORPUS_ASTRAL, true );
update_option( 'oracle_scalar_option', 'plain string', false );
update_option( 'oracle_bool_option', false, false );   // BR-OPT: false is not "absent"
update_option( 'oracle_int_option', 0, false );
update_option( 'oracle_empty_string', '', false );
// BR-OPT-06 / F-DD-09: the 150 KB heuristic that can silently de-autoload the
// routing table or the cron queue. Seeded so the boundary is observable.
update_option( 'oracle_large_option', str_repeat( 'x', 160 * 1024 ), true );
update_option( 'oracle_just_under', str_repeat( 'y', 140 * 1024 ), true );
// Site identity + permalink structure — Routing reads these (AGG-Permalink).
// ⚠️ NOT slashed. update_option() expects UNSLASHED data -- the form handlers call
// wp_unslash() before reaching it. wp_insert_post() and wp_insert_user() are the
// opposite: they expect slashed input and unslash internally. Passing wp_slash() here
// stores a LITERAL backslash before every quote, which then shows up in the feed title
// and in every golden capture. Verified against the oracle's own tables.
update_option( 'blogname', "Reversa Oracle \"7.2\" 😀" );
update_option( 'blogdescription', CORPUS_QUOTES );
update_option( 'permalink_structure', '/%year%/%monthnum%/%postname%/' );
update_option( 'category_base', '' );
update_option( 'tag_base', '' );
update_option( 'timezone_string', 'Europe/Madrid' );
update_option( 'date_format', 'F j, Y' );
update_option( 'time_format', 'g:i a' );
update_option( 'start_of_week', 1 );
update_option( 'posts_per_page', 10 );
update_option( 'default_comment_status', 'open' );
update_option( 'thread_comments', 1 );
update_option( 'thread_comments_depth', 5 );
update_option( 'comment_moderation', 0 );
update_option( 'comment_previously_approved', 1 );
// BR-CMT-08: keyword lists matched as UNQUOTED SUBSTRINGS across six fields.
// "press" here is the case that matches "WordPress" — the deviation the target fixes.
update_option( 'disallowed_keys', "press\nbadword\nhttp://spam.example" );
update_option( 'moderation_keys', "moderate-me\nreview" );
update_option( 'comment_max_links', 2 );
// The privacy-policy page is created as a DRAFT by wp_install(). web.privacy_policy is
// one of the 18 LITERAL screens in golden/manifest.yaml, so it must actually render.
$privacy = get_page_by_path( 'privacy-policy' );
if ( $privacy ) {
    if ( 'publish' !== $privacy->post_status ) {
        wp_update_post( array( 'ID' => $privacy->ID, 'post_status' => 'publish' ) );
    }
    update_option( 'wp_page_for_privacy_policy', $privacy->ID );
}

// ⚠️ Rewrite rules are DERIVED state and are not rebuilt by writing the option that
// describes them. Without this flush every pretty permalink 404s -- and because the 404
// page renders successfully, the capture reports HTTP 404 rather than an error, which
// reads like a corpus problem rather than a stale-cache one. This is F-RW-02 / AD-06's
// point made concrete: the compiled route table is derived, cached and rebuildable.
$transient_ok = set_transient( 'oracle_transient', corpus_serialized_array(), 3600 );
set_transient( 'oracle_expired_transient', 'stale', -1 );  // already expired on write
note( 'options', $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->options}" ) );
note( 'autoloaded options', $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->options} WHERE autoload IN ('yes','on','auto','auto-on')" ) );

// ── 12. A user_request row, an application password, and a session token ──────
$sm = WP_Session_Tokens::get_instance( $users['editor'] );
$sm->create( time() + 172800 );
$sm->create( time() + 86400 );
if ( function_exists( 'WP_Application_Passwords::create_new_application_password' ) || class_exists( 'WP_Application_Passwords' ) ) {
    WP_Application_Passwords::create_new_application_password( $users['editor'], array( 'name' => 'Oracle App "Password"' ) );
}
note( 'sessions (editor)', count( $sm->get_all() ) );

// ── 13. Links — the legacy table F-DD-07 calls dead weight, seeded so the ─────
//        seeding pipeline's "discarded sources" path (T-11) has something to skip.
$wpdb->insert( $wpdb->prefix . 'links', array(
    'link_url' => 'https://example.com/blogroll', 'link_name' => 'Blogroll Entry',
    'link_description' => 'A link the target discards', 'link_visible' => 'Y', 'link_owner' => 1,
) );

// ── 13b. Pin every date to a deterministic, DISTINCT instant ─────────────────
// ⚠️ wp_install() stamps "Hello world!", "Sample Page" and the privacy-policy draft with
// current_time(), i.e. the REAL clock. Those posts then sort differently on every
// rebuild, which changes which records land on page 1 of a date-ordered archive, which
// changes the rendered HTML, which makes the golden files differ between two runs of an
// otherwise identical corpus. golden/manifest.yaml names the strategy -- "fake-clock +
// fixed-seed + seeded corpus" -- and this is the seeded-corpus half of it.
// ⚠️ DISTINCT dates, not one shared instant. WP_Query orders archives by `post_date DESC`
// with NO tiebreak, so records sharing a date come back in whatever order InnoDB
// happens to produce -- which changes which post is first on an archive page, and
// therefore changes the rendered HTML between two runs of an identical corpus. Giving
// every record its own instant makes the ordering total, and it is also more faithful:
// a real site does not publish everything in the same second.
$wpdb->query(
    "UPDATE {$wpdb->posts} SET
        post_date         = DATE_SUB('$FIXED', INTERVAL ID MINUTE),
        post_date_gmt     = DATE_SUB('$FIXED', INTERVAL ID MINUTE),
        post_modified     = DATE_SUB('$FIXED', INTERVAL ID MINUTE),
        post_modified_gmt = DATE_SUB('$FIXED', INTERVAL ID MINUTE)
     WHERE post_date_gmt <> '0000-00-00 00:00:00'"
);
$wpdb->query(
    "UPDATE {$wpdb->comments} SET
        comment_date     = DATE_SUB('$FIXED', INTERVAL comment_ID MINUTE),
        comment_date_gmt = DATE_SUB('$FIXED', INTERVAL comment_ID MINUTE)"
);
$wpdb->query( $wpdb->prepare( "UPDATE {$wpdb->users} SET user_registered = %s", $FIXED ) );
wp_cache_flush();

// ── 14. Report ────────────────────────────────────────────────────────────────
echo "\n── corpus totals ─────────────────────────────────────────────\n";
foreach ( $wpdb->get_results( "SELECT post_type, post_status, COUNT(*) c FROM {$wpdb->posts} GROUP BY post_type, post_status ORDER BY post_type, post_status" ) as $r ) {
    printf( "  %-22s %-16s %d\n", $r->post_type, $r->post_status, $r->c );
}
printf( "\n  %-22s %d\n", 'distinct post types', $wpdb->get_var( "SELECT COUNT(DISTINCT post_type) FROM {$wpdb->posts}" ) );
printf( "  %-22s %d\n", 'posts total',    $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->posts}" ) );
printf( "  %-22s %d\n", 'postmeta',       $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->postmeta}" ) );
printf( "  %-22s %d\n", 'comments',       $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->comments}" ) );
printf( "  %-22s %d\n", 'terms',          $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->terms}" ) );
printf( "  %-22s %d\n", 'term_taxonomy',  $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->term_taxonomy}" ) );
printf( "  %-22s %d\n", 'term_relations', $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->term_relationships}" ) );
printf( "  %-22s %d\n", 'users',          $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->users}" ) );
printf( "  %-22s %d\n", 'usermeta',       $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->usermeta}" ) );
printf( "  %-22s %d\n", 'options',        $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->options}" ) );
printf( "  %-22s %d\n", 'zero-date rows', $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_date_gmt = '0000-00-00 00:00:00'" ) );
echo "\nSEED OK\n";
