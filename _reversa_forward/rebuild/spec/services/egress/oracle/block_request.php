<?php
/**
 * Batch oracle for the site-wide egress allowlist (BR-MIGRATE-257, BR-HTTP-13).
 *
 * The executable definition is WP_Http::block_request() (wp-includes/class-wp-http.php
 * :895). Its switches are wp-config.php CONSTANTS. The oracle's own wp-config.php already
 * sets `WP_HTTP_BLOCK_EXTERNAL = true` (blocking mode ON) and does NOT set
 * WP_ACCESSIBLE_HOSTS -- so this bridge supplies WP_ACCESSIBLE_HOSTS from the scenario
 * (defined BEFORE wp-load, since block_request() caches it in a function static), and
 * ONE fresh php process runs ONE scenario. WP_HTTP_BLOCK_EXTERNAL is left to the oracle's
 * config; the spec asserts the blocking-mode precondition from `blocking_enabled` below.
 *
 * Reads  one JSON document on stdin:
 *   { "accessible_hosts": string|null, "urls": [ b64, ... ] }
 * Writes one JSON document on stdout:
 *   { "results": [ bool, ... ], "site_host": string|null, "blocking_enabled": bool }
 *   where each result is block_request()'s verdict (true = block, false = allow).
 *
 * NO EXTERNAL NETWORK: block_request() never resolves -- it compares host strings only.
 */
$input = json_decode( stream_get_contents( STDIN ), true );

if ( array_key_exists( 'accessible_hosts', $input ) && null !== $input['accessible_hosts'] ) {
	define( 'WP_ACCESSIBLE_HOSTS', $input['accessible_hosts'] );
}

require dirname( __DIR__, 5 ) . '/oracle/wordpress/tools/_bootstrap.php';

$http    = new WP_Http();
$results = array();
foreach ( $input['urls'] as $b64 ) {
	$url       = base64_decode( $b64 );
	$results[] = (bool) $http->block_request( $url );
}

$parsed_home = wp_parse_url( get_option( 'siteurl' ) );
echo json_encode(
	array(
		'results'          => $results,
		'site_host'        => isset( $parsed_home['host'] ) ? $parsed_home['host'] : null,
		'blocking_enabled' => defined( 'WP_HTTP_BLOCK_EXTERNAL' ) && WP_HTTP_BLOCK_EXTERNAL,
	)
);
