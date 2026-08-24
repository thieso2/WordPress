<?php
/**
 * Batch oracle for the Egress SSRF differential (BC-14, PT-011).
 *
 * The executable definition of BR-MIGRATE-246..255 is wp_http_validate_url()
 * (wp-includes/http.php:559). This runner feeds it a URL corpus and reports its
 * verdict, so Egress::UrlPolicy can be diffed against the legacy rather than
 * against a Ruby-only restatement of the rules (AD-08).
 *
 * Reads  one JSON document on stdin:  { "urls": [ b64, ... ] }
 * Writes one JSON document on stdout: { "results": [ b64|null, ... ] }
 *   wp_http_validate_url() returns the (kses-cleaned) URL on accept, false on
 *   reject; here that is a base64 string on accept, null on reject.
 *
 * Every URL crosses the boundary base64-encoded: the corpus carries userinfo,
 * control bytes and deliberately malformed input that json_encode() would drop.
 *
 * NO EXTERNAL NETWORK: the corpus uses IP-literal hosts (which skip
 * gethostbyname() entirely), the site's own host, and RFC 6761 .invalid hosts
 * (which the stub resolver answers as non-existent without leaving the machine).
 */
require dirname( __DIR__, 5 ) . '/oracle/wordpress/tools/_bootstrap.php';

$input   = json_decode( stream_get_contents( STDIN ), true );
$results = array();
foreach ( $input['urls'] as $b64 ) {
	$url = base64_decode( $b64 );
	$out = wp_http_validate_url( $url );
	$results[] = is_string( $out ) ? base64_encode( $out ) : null;
}
echo json_encode( array( 'results' => $results, 'home' => get_option( 'home' ) ) );
