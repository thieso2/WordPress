<?php
/**
 * Differential-testing bridge to the PHP oracle.
 *
 * Reads a JSON array of calls on stdin, executes each one against the real
 * WordPress 7.2-alpha-63330 tree, and prints the results as JSON. Used by
 * packs/styling/spec/differential_spec.rb; it is skipped when PHP or the oracle
 * is not present.
 *
 * Supported calls:
 *   {"fn":"style_engine_get_styles","styles":{...},"selector":null,"convert":false}
 *   {"fn":"stylesheet_from_css_rules","rules":[...],"optimize":false,"prettify":false}
 *   {"fn":"safecss_filter_attr","css":"..."}
 *   {"fn":"to_kebab_case","value":"..."}
 *   {"fn":"viewport_media_queries","settings":...,"desktop":false}
 *   {"fn":"theme_json_migrate","doc":{...},"origin":"theme"}
 *   {"fn":"theme_json_merge","a":{...},"a_origin":"default","b":{...},"b_origin":"theme"}
 *   {"fn":"split_selector_list","selector":"..."}
 *   {"fn":"append_to_selector","selector":"...","append":"..."}
 *   {"fn":"prepend_to_selector","selector":"...","prepend":"..."}
 *   {"fn":"scope_selector","scope":"...","selector":"..."}
 *   {"fn":"block_style_variation_selector","variation":"...","selector":"..."}
 *   {"fn":"typography_font_size_value","preset":{...},"settings":{...}}
 *   {"fn":"blocks_metadata"}
 *   {"fn":"global_stylesheet","filter_block_nodes":true}
 *   {"fn":"global_style_block_nodes"}
 *   {"fn":"merged_theme_json"}
 */

/** WP_Theme_JSON hides most of what is worth comparing behind `protected`. */
function oracle_static($method, $args = array()) {
    $m = new ReflectionMethod('WP_Theme_JSON', $method);
    $m->setAccessible(true);
    return $m->invokeArgs(null, $args);
}

$bootstrap = getenv('WP_ORACLE_BOOTSTRAP');
if (!$bootstrap || !file_exists($bootstrap)) {
    fwrite(STDERR, "oracle bootstrap not found\n");
    exit(2);
}
require $bootstrap;

$calls = json_decode(stream_get_contents(STDIN), true);
$out = array();

foreach ($calls as $call) {
    switch ($call['fn']) {
        case 'style_engine_get_styles':
            $out[] = wp_style_engine_get_styles(
                $call['styles'],
                array(
                    'selector' => $call['selector'] ?? null,
                    'convert_vars_to_classnames' => $call['convert'] ?? false,
                )
            );
            break;
        case 'stylesheet_from_css_rules':
            $out[] = wp_style_engine_get_stylesheet_from_css_rules(
                $call['rules'],
                array('optimize' => $call['optimize'] ?? false, 'prettify' => $call['prettify'] ?? false)
            );
            break;
        case 'safecss_filter_attr':
            $out[] = safecss_filter_attr($call['css']);
            break;
        case 'to_kebab_case':
            $out[] = _wp_to_kebab_case($call['value']);
            break;
        case 'viewport_media_queries':
            $out[] = WP_Theme_JSON::get_viewport_media_queries(
                $call['settings'],
                array('include_desktop' => $call['desktop'] ?? false)
            );
            break;
        case 'theme_json_migrate':
            $out[] = WP_Theme_JSON_Schema::migrate($call['doc'], $call['origin'] ?? 'theme');
            break;
        case 'theme_json_merge':
            $a = new WP_Theme_JSON($call['a'], $call['a_origin']);
            $a->merge(new WP_Theme_JSON($call['b'], $call['b_origin']));
            $out[] = $a->get_raw_data();
            break;
        case 'split_selector_list':
            $out[] = oracle_static('split_selector_list', array($call['selector']));
            break;
        case 'append_to_selector':
            $out[] = oracle_static('append_to_selector', array($call['selector'], $call['append']));
            break;
        case 'prepend_to_selector':
            $out[] = oracle_static('prepend_to_selector', array($call['selector'], $call['prepend']));
            break;
        case 'scope_selector':
            $out[] = WP_Theme_JSON::scope_selector($call['scope'], $call['selector']);
            break;
        case 'block_style_variation_selector':
            $out[] = oracle_static('get_block_style_variation_selector', array($call['variation'], $call['selector']));
            break;
        case 'typography_font_size_value':
            $out[] = wp_get_typography_font_size_value($call['preset'], $call['settings'] ?? array());
            break;
        case 'blocks_metadata':
            $out[] = oracle_static('get_blocks_metadata');
            break;
        case 'merged_theme_json':
            $out[] = WP_Theme_JSON_Resolver::get_merged_data()->get_raw_data();
            break;
        case 'global_stylesheet':
            // script-loader.php:2605 registers this on every front-end request.
            if (!empty($call['filter_block_nodes'])) {
                add_filter('wp_theme_json_get_style_nodes', 'wp_filter_out_block_nodes');
            }
            $out[] = wp_get_global_stylesheet();
            remove_filter('wp_theme_json_get_style_nodes', 'wp_filter_out_block_nodes');
            break;
        case 'global_style_block_nodes':
            $tree = WP_Theme_JSON_Resolver::get_merged_data();
            $rows = array();
            foreach ($tree->get_styles_block_nodes() as $metadata) {
                $rows[] = array(
                    'path' => $metadata['path'],
                    'selector' => $metadata['selector'] ?? null,
                    'css' => $tree->get_styles_for_block($metadata),
                );
            }
            $out[] = $rows;
            break;
        default:
            fwrite(STDERR, "unknown call {$call['fn']}\n");
            exit(3);
    }
}

echo json_encode($out, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
