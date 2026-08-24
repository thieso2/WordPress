<?php
/**
 * Differential probe for the Library write path. Reads one JSON request on STDIN:
 *
 *   { "user": "oracle_author",
 *     "sanitize": [names],               -> sanitize_file_name()
 *     "unique_dir": "/abs/dir", "unique": [names],   -> wp_unique_filename()
 *     "files": { name: "/abs/path" },    -> wp_check_filetype_and_ext(), wp_read_image_metadata()
 *     "sideload": [ { "name", "path", "parent" } ] } -> media_handle_sideload()
 *
 * ⚠️ RISK-002: the oracle's database is read-only to the rebuild. `sideload` exercises
 * the oracle's OWN write path, inside a transaction that is ROLLED BACK, and every file
 * it left under wp-content/uploads is deleted afterwards. The response reports whether
 * the corpus is provably untouched (`clean`), and the spec refuses to pass otherwise.
 */
require "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php";
$req = json_decode(stream_get_contents(STDIN), true);

// One probe at a time. The oracle's uploads directory is shared by every suite run on
// this host, and wp_unique_filename() reads it: a concurrent probe's `oracle-image-1.png`
// would turn this one's answer into `oracle-image-2.png` — a manufactured divergence.
$lock = fopen(sys_get_temp_dir() . '/reversa-oracle-library-probe.lock', 'c');
flock($lock, LOCK_EX);
register_shutdown_function(function () use ($lock) { flock($lock, LOCK_UN); fclose($lock); });
global $wpdb;

$user = get_user_by('login', $req['user'] ?? 'oracle_author');
wp_set_current_user($user ? $user->ID : 0);

$out = ['sanitize' => [], 'unique' => [], 'filetype' => [], 'image_meta' => [], 'sideload' => [], 'clean' => true];
foreach ($req['sanitize'] ?? [] as $n) { $out['sanitize'][$n] = sanitize_file_name($n); }
foreach ($req['unique'] ?? [] as $n) { $out['unique'][$n] = wp_unique_filename($req['unique_dir'], $n); }
foreach ($req['files'] ?? [] as $n => $path) {
    $out['filetype'][$n] = wp_check_filetype_and_ext($path, $n);
    $out['image_meta'][$n] = wp_read_image_metadata($path);
}

if (!empty($req['sideload'])) {
    $basedir = wp_upload_dir()['basedir'];
    $snapshot = function () use ($basedir) {
        $files = [];
        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($basedir, FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::CHILD_FIRST);
        foreach ($it as $f) { $files[] = $f->getPathname(); }
        return $files;
    };
    $before = $snapshot();
    $posts_before = (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts}");
    $meta_before  = (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->postmeta}");
    $wpdb->query('START TRANSACTION');
    foreach ($req['sideload'] as $item) {
        $tmp = tempnam(sys_get_temp_dir(), 'probe');
        copy($item['path'], $tmp);
        $id = media_handle_sideload(['name' => $item['name'], 'tmp_name' => $tmp], (int) ($item['parent'] ?? 0));
        if (is_wp_error($id)) {
            $out['sideload'][] = ['name' => $item['name'], 'error' => $id->get_error_message()];
            @unlink($tmp);
            continue;
        }
        $p = get_post($id);
        $out['sideload'][] = [
            'name' => $item['name'], 'id' => $id, 'post_name' => $p->post_name, 'post_title' => $p->post_title,
            'post_mime_type' => $p->post_mime_type, 'post_parent' => $p->post_parent,
            'attached_file' => get_post_meta($id, '_wp_attached_file', true),
            'alt' => get_post_meta($id, '_wp_attachment_image_alt', true),
            'meta' => wp_get_attachment_metadata($id),
        ];
    }
    $wpdb->query('ROLLBACK');
    wp_cache_flush();
    foreach (array_diff($snapshot(), $before) as $path) { is_dir($path) ? @rmdir($path) : @unlink($path); }
    foreach (array_diff($snapshot(), $before) as $path) { if (is_dir($path)) { @rmdir($path); } }
    $leftover = array_diff($snapshot(), $before);
    $posts_after = (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts}");
    $meta_after  = (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->postmeta}");
    $out['clean'] = empty($leftover) && $posts_before === $posts_after && $meta_before === $meta_after;
    $out['leftover'] = array_values($leftover);
    $out['posts'] = [$posts_before, $posts_after];
}
echo json_encode($out, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
