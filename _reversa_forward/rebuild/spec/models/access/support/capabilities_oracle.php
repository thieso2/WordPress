<?php
/**
 * Differential-testing bridge for the capability matrix (map_meta_cap + has_cap).
 *
 * Prints { "fixtures": { … }, "expectations": [ … ] } where `fixtures` is the oracle's
 * own corpus projected onto the target schema (users WITH their roles, posts WITH their
 * pre-trash status, attachments, comments, terms, the post-id settings) and
 * `expectations` is what `user_can( $user_id, $cap, $object_id )` answered for every
 * corpus user (plus the anonymous user 0) x every arm the rebuild ports x every object
 * it can be asked about.
 *
 * Both halves come from the same running WordPress 7.2-alpha-63330 (AD-08): the spec
 * never hand-writes an input OR an expectation. Read-only: nothing here writes.
 */
$bootstrap = getenv('WP_ORACLE_BOOTSTRAP');
if (!$bootstrap || !file_exists($bootstrap)) { fwrite(STDERR, "oracle bootstrap not found\n"); exit(2); }
// _doing_it_wrong() (the object-less arms, BR-MIGRATE-106) may print a notice under
// WP_DEBUG; it must not land in the JSON.
ob_start();
require $bootstrap;
global $wpdb;

$settings = array();
foreach (array('page_on_front', 'page_for_posts', 'wp_page_for_privacy_policy',
               'default_category', 'default_term_category', 'default_post_tag',
               'default_term_post_tag', 'link_manager_enabled') as $name) {
    $value = get_option($name);
    $settings[$name] = ($value === false) ? false : (string) $value;
}

$users = array();
foreach (get_users(array('number' => -1, 'orderby' => 'ID', 'order' => 'ASC')) as $u) {
    $users[] = array('id' => (int) $u->ID, 'login' => $u->user_login, 'nicename' => $u->user_nicename,
                     'email' => $u->user_email, 'display_name' => $u->display_name,
                     'roles' => array_values($u->roles));
}

$posts = array();
$rows = $wpdb->get_results("SELECT * FROM {$wpdb->posts} WHERE post_type IN ('post','page') ORDER BY ID");
foreach ($rows as $p) {
    $posts[] = array(
        'id' => (int) $p->ID, 'type' => $p->post_type, 'author' => (int) $p->post_author,
        'parent' => (int) $p->post_parent, 'title' => $p->post_title, 'name' => $p->post_name,
        'status' => $p->post_status, 'date_gmt' => $p->post_date_gmt,
        'trash_status' => (string) get_post_meta($p->ID, '_wp_trash_meta_status', true),
    );
}

$assets = array();
foreach (get_posts(array('post_type' => 'attachment', 'numberposts' => -1, 'post_status' => 'inherit', 'orderby' => 'ID', 'order' => 'ASC')) as $a) {
    $assets[] = array('id' => (int) $a->ID, 'title' => $a->post_title, 'name' => $a->post_name,
                      'mime_type' => $a->post_mime_type, 'uploader' => (int) $a->post_author);
}

$post_ids = array_map(fn($p) => $p['id'], $posts);
$comments = array();
foreach ($wpdb->get_results("SELECT * FROM {$wpdb->comments} ORDER BY comment_ID") as $c) {
    // Comments hang off posts or pages here (comments.post_id -> posts); a comment on an
    // attachment has no home in the target schema and is left out of the matrix.
    if (!in_array((int) $c->comment_post_ID, $post_ids, true)) { continue; }
    $comments[] = array('id' => (int) $c->comment_ID, 'post' => (int) $c->comment_post_ID,
                        'user' => (int) $c->user_id, 'approved' => (string) $c->comment_approved,
                        'content' => $c->comment_content, 'author_name' => $c->comment_author);
}

$terms = array();
foreach (get_terms(array('taxonomy' => array('category', 'post_tag'), 'hide_empty' => false, 'orderby' => 'id')) as $t) {
    $terms[] = array('id' => (int) $t->term_id, 'taxonomy' => $t->taxonomy, 'name' => $t->name,
                     'slug' => $t->slug, 'parent' => (int) $t->parent);
}

// ── The matrix ──────────────────────────────────────────────────────────────────
$actor_ids = array_merge(array(0), array_map(fn($u) => $u['id'], $users));
$expectations = array();
$ask = function ($user_id, $cap, $kind, $object_id) use (&$expectations) {
    $allowed = $object_id === null ? user_can($user_id, $cap) : user_can($user_id, $cap, $object_id);
    $expectations[] = array('user' => $user_id, 'cap' => $cap, 'kind' => $kind,
                            'object' => $object_id, 'allowed' => (bool) $allowed);
};

$primitives = array(
    'read', 'edit_posts', 'delete_posts', 'publish_posts', 'upload_files', 'edit_published_posts',
    'edit_others_posts', 'edit_pages', 'publish_pages', 'manage_categories', 'manage_links',
    'moderate_comments', 'unfiltered_html', 'edit_css', 'manage_options', 'list_users',
    'create_users', 'edit_users', 'delete_users', 'promote_users', 'remove_users',
    'edit_theme_options', 'customize', 'delete_site', 'unfiltered_upload',
    'manage_privacy_options', 'export_others_personal_data', 'erase_others_personal_data',
    'edit_categories', 'delete_categories', 'assign_categories', 'manage_post_tags',
    'edit_post_tags', 'delete_post_tags', 'assign_post_tags', 'edit_blocks',
    'publish_blocks', 'edit_others_blocks', 'exist', 'do_not_allow', 'nonsense_cap',
    'edit_post', 'delete_page', 'read_post', 'publish_post', 'edit_comment', 'edit_term',
);

foreach ($actor_ids as $uid) {
    foreach ($primitives as $cap) { $ask($uid, $cap, 'none', null); }
    foreach ($posts as $p) {
        foreach (array('edit_post', 'delete_post', 'read_post', 'publish_post') as $cap) {
            $ask($uid, $cap, 'post', $p['id']);
        }
    }
    foreach ($assets as $a) {
        foreach (array('edit_post', 'delete_post') as $cap) { $ask($uid, $cap, 'asset', $a['id']); }
    }
    foreach ($comments as $c) { $ask($uid, 'edit_comment', 'comment', $c['id']); }
    foreach ($terms as $t) {
        foreach (array('edit_term', 'delete_term', 'assign_term') as $cap) { $ask($uid, $cap, 'term', $t['id']); }
    }
    foreach ($users as $target) {
        foreach (array('edit_user', 'delete_user', 'promote_user', 'remove_user') as $cap) {
            $ask($uid, $cap, 'user', $target['id']);
        }
    }
}

$roles = array();
foreach (array('subscriber', 'contributor', 'author', 'editor', 'administrator') as $name) {
    $caps = array_keys(array_filter(get_role($name)->capabilities));
    $caps = array_values(array_filter($caps, fn($c) => !preg_match('/^level_\d+$/', $c)));
    sort($caps);
    $roles[$name] = $caps;
}

ob_end_clean();
echo json_encode(array(
    'fixtures' => compact('settings', 'users', 'posts', 'assets', 'comments', 'terms'),
    'roles' => $roles,
    'expectations' => $expectations,
), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
