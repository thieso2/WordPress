<?php
/**
 * Differential bridge for the localization track. Reads a JSON array of typed cases on
 * stdin and prints, per case, exactly what the oracle's l10n/formatting/POMO functions
 * return. No writes -- every probe is a pure read, so no transaction is needed.
 *
 *   {"type":"sanitize","name":"..."}                     -> sanitize_locale_name()
 *   {"type":"determine","pagenow":"...","get":..,"cookie":..} -> determine_locale()
 *   {"type":"entry_key","singular":"...","context":..}   -> Translation_Entry::key()
 *   {"type":"get_locale"}                                -> get_locale()
 */
$bootstrap = getenv('WP_ORACLE_BOOTSTRAP');
if (!$bootstrap || !file_exists($bootstrap)) { fwrite(STDERR, "oracle bootstrap not found\n"); exit(2); }
require $bootstrap;

$cases = json_decode(stream_get_contents(STDIN), true);
$results = array();

foreach ($cases as $case) {
    switch ($case['type']) {
        case 'sanitize':
            $results[] = array('value' => sanitize_locale_name($case['name']));
            break;

        case 'determine':
            // determine_locale() reads these three request globals. Reset them for each
            // case so nothing bleeds between probes.
            unset($_GET['wp_lang'], $_COOKIE['wp_lang']);
            $GLOBALS['pagenow'] = $case['pagenow'];
            if (array_key_exists('get', $case) && $case['get'] !== null) {
                $_GET['wp_lang'] = $case['get'];
            }
            if (array_key_exists('cookie', $case) && $case['cookie'] !== null) {
                $_COOKIE['wp_lang'] = $case['cookie'];
            }
            $results[] = array('value' => determine_locale());
            break;

        case 'entry_key':
            $args = array('singular' => $case['singular']);
            if (array_key_exists('context', $case) && $case['context'] !== null) {
                $args['context'] = $case['context'];
            }
            $entry = new Translation_Entry($args);
            $results[] = array('value' => $entry->key());
            break;

        case 'get_locale':
            $results[] = array('value' => get_locale());
            break;

        default:
            $results[] = array('error' => 'unknown type ' . $case['type']);
    }
}

echo json_encode(array('results' => $results));
