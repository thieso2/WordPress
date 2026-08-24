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
foreach ( $out as $screen => $path ) { echo $screen . "\t" . $path . "\n"; }
