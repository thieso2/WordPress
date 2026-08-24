<?php
/**
 * Differential-testing bridge for the WP-Cron de-duplication window
 * (wp-includes/cron.php:117-169, wp_schedule_single_event()). Rules BR-MIGRATE-280 /
 * BR-MIGRATE-281 (legacy BR-CRON-04 / BR-CRON-05).
 *
 * Each case on stdin is [candidate_offset, existing[], candidate_args, candidate_hook]
 * where existing[] is a list of [offset, args, hook?]. Offsets are seconds relative to
 * time(); the bridge seeds the `cron` option DIRECTLY (bypassing dedup, so existing
 * events are placed exactly) then asks wp_schedule_single_event() whether the candidate
 * is accepted or rejected as 'duplicate_event'. Output is a JSON array of the oracle's
 * verdict per case: "scheduled" | "duplicate_event" | "<other error code>".
 */
$bootstrap = getenv('WP_ORACLE_BOOTSTRAP');
if (!$bootstrap || !file_exists($bootstrap)) { fwrite(STDERR, "oracle bootstrap not found\n"); exit(2); }
ob_start();
require $bootstrap;
ob_end_clean();
global $wpdb;

// Seeding the `cron` option mutates oracle state. Wrap everything in a transaction and roll it
// back so the oracle is left exactly as found (non-negotiable #5). The option cache is per-request
// and discarded at exit, so nothing observable survives.
$wpdb->query('START TRANSACTION');
register_shutdown_function(function () use ($wpdb) { $wpdb->query('ROLLBACK'); });

function run_case($c) {
    list($c_off, $existing, $cand_args, $cand_hook) = array_pad($c, 4, null);
    if ($cand_hook === null) $cand_hook = 'test_hook';
    $now = time();
    $crons = array();
    foreach ($existing as $e) {
        list($e_off, $e_args, $e_hook) = array_pad($e, 3, null);
        if ($e_hook === null) $e_hook = 'test_hook';
        $ts  = $now + $e_off;
        $key = md5(serialize($e_args));
        $crons[$ts][$e_hook][$key] = array('schedule' => false, 'args' => $e_args);
    }
    ksort($crons);
    _set_cron_array($crons);
    $r = wp_schedule_single_event($now + $c_off, $cand_hook, $cand_args, true);
    if (is_wp_error($r)) return $r->get_error_code();
    return $r === true ? 'scheduled' : 'false';
}

$cases = json_decode(stream_get_contents(STDIN), true);
$out = array();
foreach ($cases as $c) { $out[] = run_case($c); }
echo json_encode($out, JSON_UNESCAPED_SLASHES);
