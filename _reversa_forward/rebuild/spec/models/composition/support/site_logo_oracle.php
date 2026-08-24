<?php
/**
 * Differential bridge for `core/site-logo`'s NON-EMPTY branch.
 *
 * The oracle corpus sets no `site_logo` option, so the whole `get_custom_logo()` half of
 * site-logo.php was unreachable from post_blocks_oracle.php and went unverified. This
 * bridge supplies the option with a `pre_option_site_logo` filter, which lives in THIS
 * PHP process only — the shared oracle database is never written to.
 *
 * Reads a JSON array of block markups on stdin, prints { "asset": {…}, "rendered": [ … ] }.
 * Both the fixture and the expectation come from the running WordPress. AD-08.
 */
$bootstrap = getenv('WP_ORACLE_BOOTSTRAP');
if (!$bootstrap || !file_exists($bootstrap)) { fwrite(STDERR, "oracle bootstrap not found\n"); exit(2); }
require $bootstrap;
global $wpdb;

$id = (int) $wpdb->get_var(
    "SELECT ID FROM {$wpdb->posts} WHERE post_type='attachment' AND post_mime_type='image/png' ORDER BY ID LIMIT 1"
);
add_filter('pre_option_site_logo', static function () use ($id) { return $id; });

$row  = get_post($id);
$meta = wp_get_attachment_metadata($id);

$asset = array(
    'slug'      => $row->post_name,
    'title'     => $row->post_title,
    'alt_text'  => (string) get_post_meta($id, '_wp_attachment_image_alt', true),
    'mime_type' => $row->post_mime_type,
    'width'     => (int) $meta['width'],
    'height'    => (int) $meta['height'],
    'metadata'  => $meta,
);

$rendered = array();
foreach (json_decode(stream_get_contents(STDIN), true) as $markup) {
    $rendered[] = render_block(parse_blocks($markup)[0]);
}

echo json_encode(
    array('asset' => $asset, 'settings' => array('blogname' => get_option('blogname'),
                                                 'home' => get_option('home'),
                                                 'siteurl' => get_option('siteurl')),
          'rendered' => $rendered),
    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
);
