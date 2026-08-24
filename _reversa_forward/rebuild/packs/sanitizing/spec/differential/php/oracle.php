<?php
/**
 * Batch oracle for the sanitizing pack's differential harness.
 *
 * handoff.md, "Six things that will bite if you skip them", item 3: prove
 * PCRE/Onigmo equivalence by differential fuzzing before trusting the port.
 *
 * Reads one JSON document on stdin: { "cases": [ { "fn": "...", "args": [b64, ...] } ] }
 * Writes one JSON document on stdout: { "results": [ b64|null, ... ] }
 *
 * Every string crosses the boundary base64-encoded, because the corpus contains
 * NUL bytes, lone surrogates' byte patterns and deliberately invalid UTF-8, none
 * of which survive json_encode().
 *
 * One process, one boot of WordPress, N cases — spawning php per input is far
 * too slow to fuzz with.
 */
require dirname( __DIR__, 6 ) . '/oracle/wordpress/tools/_bootstrap.php';

$input = json_decode( stream_get_contents( STDIN ), true );
$results = array();

foreach ( $input['cases'] as $case ) {
	$args = array_map( 'base64_decode', $case['args'] );

	switch ( $case['fn'] ) {
		case 'wp_kses_post':            $out = wp_kses_post( $args[0] ); break;
		case 'wp_kses_data':            $out = wp_kses_data( $args[0] ); break;
		case 'wp_kses_strip':           $out = wp_kses( $args[0], 'strip' ); break;
		case 'wp_kses_user_description':$out = wp_kses( $args[0], 'user_description' ); break;
		case 'wp_kses_bad_protocol':    $out = wp_kses_bad_protocol( $args[0], wp_allowed_protocols() ); break;
		case 'wp_kses_normalize_entities': $out = wp_kses_normalize_entities( $args[0] ); break;
		case 'wp_kses_decode_entities': $out = wp_kses_decode_entities( $args[0] ); break;
		case 'wp_kses_no_null':         $out = wp_kses_no_null( $args[0] ); break;
		case 'wp_kses_stripslashes':    $out = wp_kses_stripslashes( $args[0] ); break;
		case 'safecss_filter_attr':     $out = safecss_filter_attr( $args[0] ); break;
		case 'esc_html':                $out = esc_html( $args[0] ); break;
		case 'esc_attr':                $out = esc_attr( $args[0] ); break;
		case 'esc_textarea':            $out = esc_textarea( $args[0] ); break;
		case 'esc_js':                  $out = esc_js( $args[0] ); break;
		case 'esc_url':                 $out = esc_url( $args[0] ); break;
		case 'esc_url_raw':             $out = esc_url_raw( $args[0] ); break;
		case 'sanitize_key':            $out = sanitize_key( $args[0] ); break;
		case 'sanitize_title':          $out = sanitize_title( $args[0] ); break;
		case 'sanitize_title_with_dashes_display': $out = sanitize_title_with_dashes( $args[0], '', 'display' ); break;
		case 'wptexturize':             $out = wptexturize( $args[0] ); break;
		case 'wpautop':                 $out = wpautop( $args[0] ); break;
		case 'wpautop_nobr':            $out = wpautop( $args[0], false ); break;
		case 'wp_pre_kses_less_than':   $out = wp_pre_kses_less_than( $args[0] ); break;
		case 'remove_accents':          $out = remove_accents( $args[0] ); break;
		case 'utf8_uri_encode_200':     $out = utf8_uri_encode( $args[0], 200 ); break;
		case '_wp_specialchars_xml':  $out = _wp_specialchars( $args[0], ENT_XML1 ); break;
		case '_wp_specialchars_noquotes': $out = _wp_specialchars( $args[0] ); break;
		case 'wp_kses_normalize_entities_xml': $out = wp_kses_normalize_entities( $args[0], 'xml' ); break;
		case 'strip_tags':             $out = strip_tags( $args[0] ); break;
		case '_deep_replace':           $out = _deep_replace( array( '%0d', '%0a', '%0D', '%0A' ), $args[0] ); break;
		default:
			fwrite( STDERR, "unknown fn: {$case['fn']}\n" );
			exit( 2 );
	}

	$results[] = is_string( $out ) ? base64_encode( $out ) : null;
}

echo json_encode( array( 'results' => $results ) );
