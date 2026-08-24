<?php
/**
 * Differential-testing bridge for wp_create_user_request() (wp-includes/user.php:4803).
 * Cases are [email, action, status] triples on stdin; every case runs inside a
 * rolled-back transaction, so the duplicate-detection case can first CREATE a request
 * and then observe the duplicate error without leaving either behind.
 */
$bootstrap = getenv('WP_ORACLE_BOOTSTRAP');
if (!$bootstrap || !file_exists($bootstrap)) { fwrite(STDERR, "oracle bootstrap not found\n"); exit(2); }
ob_start();
require $bootstrap;
global $wpdb;

$cases = json_decode(stream_get_contents(STDIN), true);
$results = array();
foreach ($cases as $case) {
    list($email, $action, $status, $precreate) = array_pad($case, 4, null);
    $wpdb->query('START TRANSACTION');
    if ($precreate) { wp_create_user_request($precreate[0], $precreate[1]); }
    $result = wp_create_user_request($email, $action, array(), $status === null ? 'pending' : $status);
    if (is_wp_error($result)) {
        $results[] = array('error' => array('code' => $result->get_error_code(), 'message' => $result->get_error_message()));
    } else {
        $p = get_post($result);
        $results[] = array('request' => array('email' => $p->post_title, 'action' => $p->post_name,
                                              'status' => $p->post_status, 'author' => (int) $p->post_author));
    }
    $wpdb->query('ROLLBACK');
}

ob_end_clean();
echo json_encode(array('results' => $results), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
