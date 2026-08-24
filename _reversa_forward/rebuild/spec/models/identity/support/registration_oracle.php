<?php
/**
 * Differential-testing bridge for self-service registration.
 *
 * Reads a JSON array of [login, email] cases on stdin and prints, per case, either the
 * WP_Error codes+messages register_new_user() produced or the user it created. Every
 * case runs inside START TRANSACTION … ROLLBACK on the oracle's own connection, so the
 * success cases exercise the real wp_insert_user() write path and leave the corpus
 * exactly as they found it (RISK-002: the oracle's database is not ours to dirty).
 */
$bootstrap = getenv('WP_ORACLE_BOOTSTRAP');
if (!$bootstrap || !file_exists($bootstrap)) { fwrite(STDERR, "oracle bootstrap not found\n"); exit(2); }
ob_start(); // wp_new_user_notification() tries sendmail; nothing it prints may reach stdout.
require $bootstrap;
global $wpdb;

$cases = json_decode(stream_get_contents(STDIN), true);
$results = array();
foreach ($cases as $case) {
    list($login, $email) = $case;
    $wpdb->query('START TRANSACTION');
    $result = register_new_user($login, $email);
    if (is_wp_error($result)) {
        $errors = array();
        foreach ($result->errors as $code => $messages) {
            foreach ($messages as $message) { $errors[] = array('code' => $code, 'message' => $message); }
        }
        $results[] = array('errors' => $errors);
    } else {
        $u = get_userdata($result);
        $results[] = array('user' => array(
            'login' => $u->user_login, 'nicename' => $u->user_nicename, 'email' => $u->user_email,
            'display_name' => $u->display_name, 'roles' => array_values($u->roles),
        ));
    }
    $wpdb->query('ROLLBACK');
}

$fixtures = array(
    'settings' => array(
        'admin_email' => (string) get_option('admin_email'),
        'default_role' => (string) get_option('default_role'),
        'users_can_register' => (string) get_option('users_can_register'),
    ),
    'login_url' => wp_login_url(),
    'users' => array(),
);
foreach (get_users(array('number' => -1, 'orderby' => 'ID')) as $u) {
    $fixtures['users'][] = array('login' => $u->user_login, 'nicename' => $u->user_nicename,
                                 'email' => $u->user_email, 'display_name' => $u->display_name);
}

ob_end_clean();
echo json_encode(array('fixtures' => $fixtures, 'results' => $results), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
