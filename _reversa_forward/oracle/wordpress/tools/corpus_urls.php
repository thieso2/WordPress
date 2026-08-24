<?php
/**
 * Emits the resolved request paths for spec/parity/corpus/requests.yml.
 *
 * The 18 literal web.* screens are addressed by permalink, and the permalinks depend on
 * permalink_structure and on the corpus's own slugs. Hand-writing them guesses; asking
 * the oracle does not. Re-run whenever the corpus changes.
 */
require_once __DIR__ . '/_bootstrap.php';
$home = home_url();
$rel = function ( $url ) use ( $home ) { return str_replace( $home, '', $url ) ?: '/'; };

$post = get_posts( array( 'numberposts' => 1, 'post_status' => 'publish', 'orderby' => 'ID', 'order' => 'ASC' ) )[0];
$page = get_page_by_path( 'parent-page' );
$att  = get_posts( array( 'post_type' => 'attachment', 'numberposts' => 1, 'post_status' => 'inherit' ) )[0];
$priv = get_page_by_path( 'privacy-policy' );
$cat  = get_term_by( 'slug', 'top-category', 'category' );
$leaf = get_term_by( 'slug', 'middle-category', 'category' );
$tag  = get_term_by( 'slug', 'flat-tag-one', 'post_tag' );
$author = get_user_by( 'login', 'oracle_author' );

$out = array(
  'web.index'          => '/',
  'web.front_page'     => '/',
  'web.home'           => '/',
  'web.singular'       => $rel( get_permalink( $post ) ),
  'web.single'         => $rel( get_permalink( $post ) ),
  'web.page'           => $rel( get_permalink( $page ) ),
  'web.archive'        => $rel( get_year_link( (int) get_the_date( 'Y', $post ) ) ),
  'web.category'       => $rel( get_term_link( $cat ) ),
  'web.tag'            => $rel( get_term_link( $tag ) ),
  'web.taxonomy'       => $rel( get_term_link( $leaf ) ),
  'web.author'         => $rel( get_author_posts_url( $author->ID ) ),
  'web.date'           => $rel( get_month_link( (int) get_the_date( 'Y', $post ), (int) get_the_date( 'n', $post ) ) ),
  'web.search'         => '/?s=article',
  'web.not_found_404'  => '/definitely-not-a-real-url/',
  'web.attachment'     => $rel( get_permalink( $att ) ),
  'web.embed'          => $rel( get_post_embed_url( $post ) ),
  'web.privacy_policy' => $rel( get_permalink( $priv ) ),
  'web.comments'       => $rel( get_permalink( $post ) ),
);

// ── Corpus widening, 2026-08-24. Same rule as above: ASK, do not hand-write. Anything
// derived from a permalink, a term link or an author link is resolved here; the literal
// rewrite forms (/page/N/, /YYYY/MM/DD/) are composed from resolved parts.
// ⚠️ NOT get_posts(): its `post_status => 'any'` still applies the read permission map,
// so the private and future articles come back empty for a CLI user. The corpus needs
// their permalinks precisely BECAUSE they are unreadable — the screen is the 404.
$post_by  = function ( $slug ) { global $wpdb; $id = (int) $wpdb->get_var( $wpdb->prepare( "SELECT ID FROM {$wpdb->posts} WHERE post_name = %s AND post_type = 'post' LIMIT 1", $slug ) ); return $id ? array( get_post( $id ) ) : array(); };
$deep_cat = get_term_by( 'slug', 'leaf-category', 'category' );
$def_cat  = get_term_by( 'slug', 'uncategorized', 'category' );
$emoji_tag = get_term_by( 'slug', 'tag-with-%f0%9f%98%80-emoji', 'post_tag' );
$editor   = get_user_by( 'login', 'oracle_editor' );
$year     = (int) get_the_date( 'Y', $post );
$month    = (int) get_the_date( 'n', $post );
$day      = (int) get_the_date( 'j', $post );
$pbase    = $GLOBALS['wp_rewrite']->pagination_base;
$pretty = function ( $p ) {
    return '/' . get_the_date( 'Y/m', $p ) . '/' . $p->post_name . '/';
};
$mk = function ( $slug ) use ( $post_by, $rel ) {
    $found = $post_by( $slug );
    return $found ? $rel( get_permalink( $found[0] ) ) : "!! no post named {$slug}";
};

$wide = array(
  'web.home_paged'                 => "/{$pbase}/2/",
  'web.home_paged_beyond_last'     => "/{$pbase}/3/",
  'web.archive_year_paged'         => rtrim( $rel( get_year_link( $year ) ), '/' ) . "/{$pbase}/2/",
  'web.date_month_paged'           => rtrim( $rel( get_month_link( $year, $month ) ), '/' ) . "/{$pbase}/2/",
  'web.category_paged_empty'       => rtrim( $rel( get_term_link( $cat ) ), '/' ) . "/{$pbase}/2/",
  'web.date_day'                   => $rel( get_day_link( $year, $month, $day ) ),
  'web.date_day_paged'             => rtrim( $rel( get_day_link( $year, $month, $day ) ), '/' ) . "/{$pbase}/2/",
  'web.date_empty'                 => $rel( get_month_link( (int) gmdate( 'Y' ), (int) gmdate( 'n' ) ) ),
  'web.category_deep'              => $rel( get_term_link( $deep_cat ) ),
  'web.category_default'           => $rel( get_term_link( $def_cat ) ),
  'web.tag_percent_encoded'        => $rel( get_term_link( $emoji_tag ) ),
  'web.author_no_posts'            => $rel( get_author_posts_url( $editor->ID ) ),
  'web.search_no_results'          => '/?s=zzzznotfoundzzzz',
  'web.page_child'                 => $rel( get_permalink( get_page_by_path( 'parent-page/child-page' ) ) ),
  'web.page_deep_duplicate_slug'   => $rel( get_permalink( get_page_by_path( 'parent-page/child-page/grandchild-page/child-page' ) ) ),
  'web.single_password_protected'  => $mk( 'password-protected' ),
  // ⚠️ get_permalink() answers `/?p=N` for a post that is not publicly readable — it
  // refuses to build a pretty permalink for one. The corpus needs the PRETTY form,
  // because that is the URL a visitor follows (a link shared while the post was public,
  // a scheduled post's preview link that leaked) and answering it is the screen under
  // test. Composed from the post's OWN date and post_name plus the permastruct, so every
  // part still comes from the oracle.
  'web.single_private_anonymous'   => $pretty( $post_by( 'private-article' )[0] ),
  'web.single_scheduled_anonymous' => $pretty( $post_by( 'scheduled-for-the-future' )[0] ),
  'web.single_kses'                => $mk( 'kses-payload-carrier' ),
  'web.single_sticky'              => $mk( 'sticky-front-page-article' ),
  'web.single_astral_slug'         => $rel( get_permalink( 11 ) ),
  'web.single_backslash_title'     => $rel( get_permalink( 12 ) ),
  'web.single_long_slug'           => $rel( get_permalink( 15 ) ),
  'web.embed_password_protected'   => $rel( get_post_embed_url( $post_by( 'password-protected' )[0] ) ),
  'web.embed_astral_slug'          => $rel( get_post_embed_url( get_post( 11 ) ) ),
  // Literal rewrite forms — no permalink to resolve, listed so the tool covers the whole
  // corpus rather than only the part that happens to be permalink-derived.
  'syndication.feed_rss2'          => '/feed/',
  'syndication.feed_atom'          => '/feed/atom/',
  'syndication.feed_comments'      => '/comments/feed/',
  'syndication.sitemap_index'      => '/wp-sitemap.xml',
  'syndication.sitemap_posts'      => '/wp-sitemap-posts-post-1.xml',
  'syndication.sitemap_users'      => '/wp-sitemap-users-1.xml',
  'syndication.robots'             => '/robots.txt',
  'syndication.sitemap_pages'      => '/wp-sitemap-posts-page-1.xml',
  'syndication.sitemap_taxonomies_category' => '/wp-sitemap-taxonomies-category-1.xml',
  'syndication.sitemap_taxonomies_post_tag' => '/wp-sitemap-taxonomies-post_tag-1.xml',
);
$out = array_merge( $out, $wide );

foreach ( $out as $screen => $path ) { echo $screen . "\t" . $path . "\n"; }
