<?php
/**
 * Rebuild all derived state in a FRESH process, after seed.php.
 *
 * ⚠️ Must be a separate php invocation from seed.php. Running the flush inside the
 * seeding process yields rewrite rules with no category/tag rules — stale $wp_rewrite
 * state that init() does not fully reset once the process has been inserting content.
 * A fresh bootstrap (wp-load → init → create_initial_taxonomies → flush) is the only
 * reliable producer of the complete rule set. Verified: fresh flush → 5 category rules.
 */
require_once __DIR__ . '/_bootstrap.php';
global $wp_rewrite;
$wp_rewrite->init();
$wp_rewrite->flush_rules( true );

foreach ( array( 'category', 'post_tag' ) as $tax ) {
    $ids = get_terms( array( 'taxonomy' => $tax, 'hide_empty' => false, 'fields' => 'tt_ids' ) );
    if ( $ids && ! is_wp_error( $ids ) ) {
        wp_update_term_count_now( $ids, $tax );
    }
}

$rules = get_option( 'rewrite_rules' );
$cat = is_array( $rules ) ? count( preg_grep( '#category#', array_keys( $rules ) ) ) : 0;
$tag = is_array( $rules ) ? count( preg_grep( '#(^|/)tag/#', array_keys( $rules ) ) ) : 0;
if ( $cat < 1 ) {
    fwrite( STDERR, "FLUSH FAILED: no category rules in the rewrite table.\n" );
    exit( 1 );
}
$top = get_term_by( 'slug', 'top-category', 'category' );
echo "flush OK: {$cat} category rules, {$tag} tag rules, top-category count=" . ( $top ? $top->count : '?' ) . "\n";
