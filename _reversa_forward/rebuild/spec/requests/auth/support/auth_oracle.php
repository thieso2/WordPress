<?php
/**
 * Differential-testing bridge for the authentication surface.
 *
 * The auth write paths -- wp_signon() (a session token + clearing user_activation_key),
 * retrieve_password() / get_password_reset_key() (writing user_activation_key) -- all
 * mutate wp_users / wp_usermeta. Driving wp-login.php over HTTP would persist those
 * mutations into the shared corpus, which RISK-002 forbids ("the oracle's database is
 * not ours to dirty"). So each case runs inside START TRANSACTION … ROLLBACK on the
 * oracle's own connection, exactly as spec/models/identity/support/registration_oracle.php
 * does, and returns only the observable facts: the WP_Error codes+messages, or the
 * capability answers wp-login.php's post-login landing (:1415-1428) branches on.
 *
 * Reads {"op":..., ...} objects, one per line, on stdin; prints a JSON array of results.
 */
$bootstrap = getenv('WP_ORACLE_BOOTSTRAP');
if (!$bootstrap || !file_exists($bootstrap)) { fwrite(STDERR, "oracle bootstrap not found\n"); exit(2); }
ob_start(); // retrieve_password() / wp_new_user_notification() try sendmail; keep their output off stdout.
require $bootstrap;
global $wpdb;

function wp_error_payload($result) {
    $errors = array();
    foreach ($result->errors as $code => $messages) {
        $severity = $result->get_error_data($code);
        foreach ($messages as $message) {
            $errors[] = array('code' => $code, 'message' => $message, 'severity' => $severity);
        }
    }
    return $errors;
}

$results = array();
foreach (explode("\n", trim(stream_get_contents(STDIN))) as $line) {
    if ($line === '') { continue; }
    $c = json_decode($line, true);
    $wpdb->query('START TRANSACTION');

    switch ($c['op']) {
        case 'signon':
            // wp_signon() with the same $_POST wp-login.php hands it (log/pwd/rememberme).
            $_POST['log'] = $c['log']; $_POST['pwd'] = $c['pwd'];
            $user = wp_signon(array(), false);
            if (is_wp_error($user)) {
                $results[] = array('error_codes' => array_keys($user->errors), 'errors' => wp_error_payload($user));
            } else {
                // The facts wp-login.php:1415-1428 branches on for the landing.
                $results[] = array('user_login' => $user->user_login,
                                   'edit_posts' => $user->has_cap('edit_posts'),
                                   'read' => $user->has_cap('read'),
                                   'manage_options' => $user->has_cap('manage_options'));
            }
            unset($_POST['log'], $_POST['pwd']);
            break;

        case 'retrieve_password':
            $result = retrieve_password($c['user_login']);
            if (is_wp_error($result)) {
                $results[] = array('error_codes' => array_keys($result->errors), 'errors' => wp_error_payload($result));
            } else {
                $results[] = array('sent' => true);
            }
            break;

        case 'check_reset_key':
            // get_password_reset_key() writes the key; check_password_reset_key() reads it.
            $user = get_user_by('login', $c['login']);
            $key = ($c['key'] === '__valid__') ? get_password_reset_key($user) : $c['key'];
            $checked = check_password_reset_key($key, $c['login']);
            if (is_wp_error($checked)) {
                $results[] = array('error_code' => $checked->get_error_code(), 'message' => $checked->get_error_message());
            } else {
                $results[] = array('user_login' => $checked->user_login);
            }
            break;

        default:
            $results[] = array('unknown_op' => $c['op']);
    }

    $wpdb->query('ROLLBACK');
}

ob_end_clean();
echo json_encode($results, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
