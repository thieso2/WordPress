<?php
/**
 * Oracle probe for AGG-Post's accepted commands (target_domain_model.md § AGG-Post):
 * create, update, publish, schedule, unpublish, trash, restore, delete, revise.
 *
 * Runs each command on the live WordPress 7.2-alpha-63330 oracle through its own API
 * (wp_insert_post, wp_update_post, wp_trash_post, wp_untrash_post, wp_delete_post,
 * wp_save_post_revision, wp_create_post_autosave) and prints the resulting ROW STATE as
 * JSON. spec/models/publishing/commands_differential_spec.rb compares the rebuild to it.
 *
 * ⚠️ RISK-002: this WRITES to the oracle's MySQL through WordPress's own write path — the
 * one thing the oracle's endpoints exist for — and never touches the database directly.
 * It cleans up everything it created (force delete) so the seeded corpus is left as it
 * was found; `bin/oracle reseed` restores it fully if anything is interrupted.
 */
require_once '/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php';

wp_set_current_user( 1 );
$out     = array();
$created = array();

function probe_row( $id ) {
	global $wpdb;
	$r = $wpdb->get_row( $wpdb->prepare( "SELECT post_status, post_name, post_date, post_date_gmt, post_modified_gmt, post_parent, post_type FROM {$wpdb->posts} WHERE ID = %d", $id ), ARRAY_A );
	return $r ?: null;
}
function probe_revisions( $id ) {
	global $wpdb;
	return $wpdb->get_results( $wpdb->prepare( "SELECT post_name, post_title, post_content FROM {$wpdb->posts} WHERE post_parent = %d AND post_type = 'revision' ORDER BY ID ASC", $id ), ARRAY_A );
}
function probe_meta( $id, $key ) {
	return get_post_meta( $id, $key );
}
function probe_term_count( $term_id ) {
	global $wpdb;
	return (int) $wpdb->get_var( $wpdb->prepare( "SELECT count FROM {$wpdb->term_taxonomy} WHERE term_id = %d", $term_id ) );
}

// ── create ──────────────────────────────────────────────────────────────────────
$id        = wp_insert_post( array( 'post_title' => 'Reversa probe', 'post_content' => 'v1', 'post_status' => 'draft', 'post_type' => 'post' ), true );
$created[] = $id;
$out['create_draft'] = probe_row( $id );
$out['create_draft_revisions'] = count( probe_revisions( $id ) );

// ── classification for the counter cascade (BR-TAX-11) ─────────────────────────
$term = wp_insert_term( 'Reversa probe category', 'category', array( 'slug' => 'reversa-probe-category' ) );
$term_id = $term['term_id'];
wp_set_post_terms( $id, array( $term_id ), 'category' );
$out['count_after_assign_to_draft'] = probe_term_count( $term_id );

// ── publish ─────────────────────────────────────────────────────────────────────
wp_update_post( array( 'ID' => $id, 'post_status' => 'publish' ) );
$out['publish'] = probe_row( $id );
$out['publish_revisions'] = probe_revisions( $id );
$out['count_after_publish'] = probe_term_count( $term_id );

// ── unpublish (status back to draft) ────────────────────────────────────────────
wp_update_post( array( 'ID' => $id, 'post_status' => 'draft' ) );
$out['unpublish'] = probe_row( $id );
$out['count_after_unpublish'] = probe_term_count( $term_id );

// ── republish, then update with a slug change (AD-03: _wp_old_slug) ─────────────
wp_update_post( array( 'ID' => $id, 'post_status' => 'publish' ) );
$out['republish'] = probe_row( $id ); // post.php:4748 — the instant comes from the merged row, not "now"
wp_update_post( array( 'ID' => $id, 'post_name' => 'reversa-probe-renamed' ) );
$out['rename'] = probe_row( $id );
$out['rename_old_slugs'] = probe_meta( $id, '_wp_old_slug' );
// renaming back removes the old slug from the list
wp_update_post( array( 'ID' => $id, 'post_name' => 'reversa-probe' ) );
$out['rename_back_old_slugs'] = probe_meta( $id, '_wp_old_slug' );

// ── revise ──────────────────────────────────────────────────────────────────────
$out['revisions_to_keep'] = wp_revisions_to_keep( get_post( $id ) );
wp_update_post( array( 'ID' => $id, 'post_content' => 'v2' ) );
$out['revise_after_content_change'] = probe_revisions( $id );
wp_update_post( array( 'ID' => $id, 'post_content' => 'v2' ) );
$out['revise_after_no_change'] = probe_revisions( $id );
wp_update_post( array( 'ID' => $id, 'post_content' => "v2  \n" ) ); // whitespace only
$out['revise_after_whitespace_change'] = probe_revisions( $id );
wp_update_post( array( 'ID' => $id, 'post_title' => 'Reversa probe v3' ) );
$out['revise_after_title_change'] = probe_revisions( $id );

// ── autosave ────────────────────────────────────────────────────────────────────
$a1 = wp_create_post_autosave( array( 'post_ID' => $id, 'post_title' => 'Reversa probe v3', 'post_content' => 'autosaved A', 'post_excerpt' => '', 'post_type' => 'post' ) );
$out['autosave_first'] = probe_revisions( $id );
$a2 = wp_create_post_autosave( array( 'post_ID' => $id, 'post_title' => 'Reversa probe v3', 'post_content' => 'autosaved B', 'post_excerpt' => '', 'post_type' => 'post' ) );
$out['autosave_second_same_author'] = probe_revisions( $id );
$out['autosave_ids_equal'] = ( (int) $a1 === (int) $a2 );
$a3 = wp_create_post_autosave( array( 'post_ID' => $id, 'post_title' => 'Reversa probe v3', 'post_content' => 'v2', 'post_excerpt' => '', 'post_type' => 'post' ) );
$out['autosave_identical_to_post'] = probe_revisions( $id );
$out['autosave_identical_return'] = $a3;

// ── schedule ────────────────────────────────────────────────────────────────────
$future = gmdate( 'Y-m-d H:i:s', time() + 2 * DAY_IN_SECONDS );
wp_update_post( array( 'ID' => $id, 'post_status' => 'publish', 'post_date_gmt' => $future, 'post_date' => get_date_from_gmt( $future ) ) );
$out['schedule'] = probe_row( $id );
$out['schedule_cron_event'] = (bool) wp_next_scheduled( 'publish_future_post', array( $id ) );
$out['count_while_scheduled'] = probe_term_count( $term_id );
// the moment arrives: what cron would do
$past = gmdate( 'Y-m-d H:i:s', time() - 120 );
global $wpdb;
$wpdb->update( $wpdb->posts, array( 'post_date_gmt' => $past, 'post_date' => get_date_from_gmt( $past ) ), array( 'ID' => $id ) );
clean_post_cache( $id );
check_and_publish_future_post( $id );
$out['publish_due'] = probe_row( $id );
$out['count_after_due'] = probe_term_count( $term_id );

// ── trash / restore ─────────────────────────────────────────────────────────────
wp_trash_post( $id );
$out['trash'] = probe_row( $id );
$out['trash_meta_status'] = probe_meta( $id, '_wp_trash_meta_status' );
$out['trash_desired_slug'] = probe_meta( $id, '_wp_desired_post_slug' );
$out['count_after_trash'] = probe_term_count( $term_id );
wp_untrash_post( $id );
$out['restore'] = probe_row( $id );
$out['restore_meta_status'] = probe_meta( $id, '_wp_trash_meta_status' );

// ── delete: what goes with the record ───────────────────────────────────────────
$parent    = wp_insert_post( array( 'post_title' => 'Reversa probe parent', 'post_type' => 'page', 'post_status' => 'publish' ), true );
$victim    = wp_insert_post( array( 'post_title' => 'Reversa probe victim', 'post_type' => 'page', 'post_status' => 'publish', 'post_parent' => $parent ), true );
$child     = wp_insert_post( array( 'post_title' => 'Reversa probe child', 'post_type' => 'page', 'post_status' => 'publish', 'post_parent' => $victim ), true );
$created[] = $parent; $created[] = $child;
add_post_meta( $victim, 'reversa_probe_key', 'value' );
wp_update_post( array( 'ID' => $victim, 'post_content' => 'revised' ) );
$comment = wp_insert_comment( array( 'comment_post_ID' => $victim, 'comment_content' => 'probe', 'comment_approved' => 1, 'comment_author' => 'probe', 'comment_author_email' => 'probe@example.com' ) );
$out['delete_before'] = array(
	'revisions' => count( probe_revisions( $victim ) ),
	'comments'  => (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$wpdb->comments} WHERE comment_post_ID = %d", $victim ) ),
	'meta'      => (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$wpdb->postmeta} WHERE post_id = %d", $victim ) ),
	'child_parent' => (int) probe_row( $child )['post_parent'] === $victim,
);
wp_delete_post( $victim, true );
$out['delete_after'] = array(
	'row'       => probe_row( $victim ),
	'revisions' => count( probe_revisions( $victim ) ),
	'comments'  => (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$wpdb->comments} WHERE comment_post_ID = %d", $victim ) ),
	'meta'      => (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$wpdb->postmeta} WHERE post_id = %d", $victim ) ),
	'child_reparented_to' => (int) probe_row( $child )['post_parent'] === $parent ? 'grandparent' : (string) probe_row( $child )['post_parent'],
	'term_relationships' => (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$wpdb->term_relationships} WHERE object_id = %d", $victim ) ),
);
// delete the classified post: the count follows
wp_delete_post( $id, true );
$out['count_after_delete'] = probe_term_count( $term_id );
$out['delete_classified_relationships'] = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$wpdb->term_relationships} WHERE object_id = %d", $id ) );

// ── normalize_whitespace (formatting.php:5590), the comparison behind every revise ────
// hex, so that the bytes PHP's trim() does and does not strip travel unambiguously.
$out['normalize_whitespace'] = array();
foreach ( array( "  a  b\t\tc  ", "x\r\ny\rz\n\n\nw", "\fform feed\f", "\0nul\0", "\x0Bvt\x0B", "tab\tend\t", "  ", "\xc3\xa9  \xc3\xbc\r\n" ) as $case ) {
	$out['normalize_whitespace'][ bin2hex( $case ) ] = bin2hex( normalize_whitespace( $case ) );
}

// ── cleanup ─────────────────────────────────────────────────────────────────────
foreach ( $created as $pid ) { wp_delete_post( $pid, true ); }
wp_delete_term( $term_id, 'category' );

echo json_encode( $out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES ), "\n";
