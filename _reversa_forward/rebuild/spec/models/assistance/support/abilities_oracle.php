<?php
/**
 * Differential-testing bridge for the Abilities API (BR-MIGRATE-269..275).
 *
 * Registers a fixed set of abilities against the oracle's WP_Abilities_Registry and prints,
 * as JSON, the observable facts the rebuild must match: the registration outcomes (a registered
 * ability vs a null return), the defaults for `public`/`show_in_rest`, and — for a battery of
 * execute() cases — the resulting value or WP_Error code together with the ORDER in which the
 * permission and execute callbacks ran. That order log is how BR-AI-05 (pipeline order) and
 * BR-AI-07 (permissions after input validation) are made observable from outside: a malformed
 * input must leave the log empty (neither callback ran), a denied permission must show only the
 * permission callback, a bad output must show both.
 *
 * Registration must happen on the wp_abilities_api_init / wp_abilities_api_categories_init
 * actions (abilities-api.php:291,646) — the hook system is the oracle's mechanism, not a rule the
 * rebuild reproduces (AD-01), so the bridge cooperates with it here purely to read the oracle.
 */
$bootstrap = getenv('WP_ORACLE_BOOTSTRAP');
if (!$bootstrap || !file_exists($bootstrap)) { fwrite(STDERR, "oracle bootstrap not found\n"); exit(2); }
ob_start();
require $bootstrap;

$GLOBALS['ability_order'] = array();
$GLOBALS['registration_outcomes'] = array();

add_action('wp_abilities_api_categories_init', function () {
    wp_register_ability_category('demo', array('label' => 'Demo', 'description' => 'Demo category'));
});

add_action('wp_abilities_api_init', function () {
    $rec_perm = function ($input = null) { $GLOBALS['ability_order'][] = 'perm'; return true; };
    $rec_exec = function ($input = null) { $GLOBALS['ability_order'][] = 'exec'; return array('n' => $input['n']); };

    // echo: object input {n:int}, object output {n:int}
    wp_register_ability('demo/echo', array(
        'label' => 'Echo', 'description' => 'Echoes n', 'category' => 'demo',
        'input_schema'  => array('type' => 'object', 'properties' => array('n' => array('type' => 'integer')), 'required' => array('n')),
        'output_schema' => array('type' => 'object', 'properties' => array('n' => array('type' => 'integer'))),
        'permission_callback' => $rec_perm, 'execute_callback' => $rec_exec,
    ));

    // deny: permission always denies
    wp_register_ability('demo/deny', array(
        'label' => 'Deny', 'description' => 'Denied', 'category' => 'demo',
        'input_schema' => array('type' => 'object', 'properties' => array('n' => array('type' => 'integer'))),
        'permission_callback' => function ($i = null) { $GLOBALS['ability_order'][] = 'perm'; return false; },
        'execute_callback' => function ($i = null) { $GLOBALS['ability_order'][] = 'exec'; return $i; },
    ));

    // badout: output schema wants integer, callback returns a string
    wp_register_ability('demo/badout', array(
        'label' => 'BadOut', 'description' => 'Bad output', 'category' => 'demo',
        'output_schema' => array('type' => 'integer'),
        'permission_callback' => function () { $GLOBALS['ability_order'][] = 'perm'; return true; },
        'execute_callback' => function () { $GLOBALS['ability_order'][] = 'exec'; return 'a string'; },
    ));

    // noschema: no input schema at all
    wp_register_ability('demo/noschema', array(
        'label' => 'NoSchema', 'description' => 'No schema', 'category' => 'demo',
        'permission_callback' => function () { $GLOBALS['ability_order'][] = 'perm'; return true; },
        'execute_callback' => function () { $GLOBALS['ability_order'][] = 'exec'; return 'ok'; },
    ));

    // pub: public true -> seeds show_in_rest true
    wp_register_ability('demo/pub', array(
        'label' => 'Pub', 'description' => 'Public', 'category' => 'demo',
        'meta' => array('public' => true),
        'permission_callback' => '__return_true', 'execute_callback' => function () { return true; },
    ));

    // ---- registration outcome probes, recorded as booleans/nulls ----
    $out = array();
    $out['duplicate']   = wp_register_ability('demo/echo', array('label' => 'x', 'description' => 'y', 'category' => 'demo', 'permission_callback' => '__return_true', 'execute_callback' => '__return_true'));
    $out['bad_name']    = wp_register_ability('noNamespace', array('label' => 'x', 'description' => 'y', 'category' => 'demo', 'permission_callback' => '__return_true', 'execute_callback' => '__return_true'));
    $out['no_category'] = wp_register_ability('demo/orphan', array('label' => 'x', 'description' => 'y', 'category' => 'missing', 'permission_callback' => '__return_true', 'execute_callback' => '__return_true'));
    $out['uppercase']   = wp_register_ability('demo/Echo-Upper', array('label' => 'x', 'description' => 'y', 'category' => 'demo', 'permission_callback' => '__return_true', 'execute_callback' => '__return_true'));

    $GLOBALS['registration_outcomes'] = array(
        'duplicate_is_null'   => $out['duplicate'] === null,
        'bad_name_is_null'    => $out['bad_name'] === null,
        'no_category_is_null' => $out['no_category'] === null,
        'uppercase_is_null'   => $out['uppercase'] === null,
    );
});

// Force the init actions to fire.
wp_get_ability('demo/echo');

function run_case($ability_name, $input, $has_input) {
    $GLOBALS['ability_order'] = array();
    $ability = wp_get_ability($ability_name);
    $result = $has_input ? $ability->execute($input) : $ability->execute();
    return array(
        'code'  => is_wp_error($result) ? $result->get_error_code() : null,
        'value' => is_wp_error($result) ? null : $result,
        'order' => $GLOBALS['ability_order'],
    );
}

$echo = wp_get_ability('demo/echo');
$pub  = wp_get_ability('demo/pub');

$report = array(
    'defaults' => array(
        'echo_public'       => (bool) $echo->get_meta_item('public'),
        'echo_show_in_rest' => (bool) $echo->get_meta_item('show_in_rest'),
        'pub_public'        => (bool) $pub->get_meta_item('public'),
        'pub_show_in_rest'  => (bool) $pub->get_meta_item('show_in_rest'),
    ),
    'registration' => $GLOBALS['registration_outcomes'],
    'cases' => array(
        'valid'          => run_case('demo/echo', array('n' => 5), true),
        'malformed'      => run_case('demo/echo', array('n' => 'not-an-int'), true),
        'denied'         => run_case('demo/deny', array('n' => 1), true),
        'bad_output'     => run_case('demo/badout', null, false),
        'missing_schema' => run_case('demo/noschema', array('x' => 1), true),
        'noschema_null'  => run_case('demo/noschema', null, false),
    ),
);

ob_end_clean();
echo json_encode($report, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
