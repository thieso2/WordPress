<?php
/**
 * Differential harness: dumps a canonical token trace from the legacy WP_HTML_Tag_Processor
 * and WP_HTML_Processor for each input on stdin (a JSON array of base64 strings).
 *
 * The Ruby specs in packs/markup/spec produce the identical structure from the port and
 * compare the two. Output is JSON so byte-exact values survive the round trip.
 */
require "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php";

$inputs = json_decode( stream_get_contents( STDIN ), true );
$results = array();

foreach ( $inputs as $encoded ) {
	$html = base64_decode( $encoded );

	// ── Tag Processor trace ────────────────────────────────────────────────────
	$tag_trace = array();
	$p = new WP_HTML_Tag_Processor( $html );
	$guard = 0;
	while ( $p->next_token() && ++$guard < 5000 ) {
		$names = $p->get_attribute_names_with_prefix( '' );
		$attrs = array();
		if ( is_array( $names ) ) {
			foreach ( $names as $name ) {
				$value = $p->get_attribute( $name );
				$attrs[] = array( $name, true === $value ? true : base64_encode( $value ) );
			}
		}
		$classes = array();
		foreach ( $p->class_list() as $class_name ) {
			$classes[] = $class_name;
		}
		$doctype = $p->get_doctype_info();
		$full_comment = $p->get_full_comment_text();
		$tag_trace[] = array(
			'type'     => $p->get_token_type(),
			'name'     => $p->get_token_name(),
			'closer'   => $p->is_tag_closer(),
			'self'     => $p->has_self_closing_flag(),
			'comment'  => $p->get_comment_type(),
			'text'     => base64_encode( $p->get_modifiable_text() ),
			'attrs'    => $attrs,
			'ns'       => $p->get_namespace(),
			'classes'  => $classes,
			'has_test' => $p->has_class( 'test' ),
			'has_a'    => $p->has_class( 'a' ),
			'full_comment' => null === $full_comment ? null : base64_encode( $full_comment ),
			'doctype'  => null === $doctype ? null : array(
				$doctype->name,
				$doctype->public_identifier,
				$doctype->system_identifier,
				$doctype->indicated_compatibility_mode,
			),
		);
	}
	$tag_paused = $p->paused_at_incomplete_token();

	// ── HTML Processor trace ───────────────────────────────────────────────────
	$tree_trace = array();
	$error      = null;
	$message    = null;
	$processor  = WP_HTML_Processor::create_fragment( $html );
	if ( null === $processor ) {
		$error = 'could-not-create';
	} else {
		$guard = 0;
		while ( $processor->next_token() && ++$guard < 5000 ) {
			$tree_trace[] = array(
				'name'   => $processor->get_token_name(),
				'type'   => $processor->get_token_type(),
				'closer' => $processor->is_tag_closer(),
				'crumbs' => $processor->get_breadcrumbs(),
				'depth'  => $processor->get_current_depth(),
			);
		}
		$error = $processor->get_last_error();
		$e     = $processor->get_unsupported_exception();
		if ( $e ) {
			$message = $e->getMessage();
		}
	}

	// ── Full-document parser trace (BR-MIGRATE-223: head/frameset/after-body) ──
	$full_trace = array();
	$full_error = null;
	$full_message = null;
	$full = WP_HTML_Processor::create_full_parser( $html );
	if ( null === $full ) {
		$full_error = 'could-not-create';
	} else {
		$guard = 0;
		while ( $full->next_token() && ++$guard < 5000 ) {
			$full_trace[] = array(
				'name'   => $full->get_token_name(),
				'type'   => $full->get_token_type(),
				'closer' => $full->is_tag_closer(),
				'crumbs' => $full->get_breadcrumbs(),
			);
		}
		$full_error = $full->get_last_error();
		$fe = $full->get_unsupported_exception();
		if ( $fe ) {
			$full_message = $fe->getMessage();
		}
	}

	// ── Tree-parser seek round trip (BR-MIGRATE-221 inside BR-MIGRATE-223) ─────
	$seek_result = null;
	foreach ( array( 'fragment', 'full' ) as $kind ) {
		$s = 'fragment' === $kind
			? WP_HTML_Processor::create_fragment( $html )
			: WP_HTML_Processor::create_full_parser( $html );
		if ( null === $s ) {
			$seek_result[ $kind ] = 'could-not-create';
			continue;
		}
		$marked = null;
		$count  = 0;
		$guard  = 0;
		while ( $s->next_tag() && ++$guard < 2000 ) {
			// Bookmark the second tag that actually appears in the text; virtual nodes
			// cannot carry a bookmark.
			if ( null === $marked && $s->set_bookmark( 'probe' ) ) {
				++$count;
				if ( 2 === $count ) {
					$s->set_bookmark( 'target' );
					$marked = $s->get_breadcrumbs();
				}
			}
		}
		if ( null === $marked || ! $s->has_bookmark( 'target' ) ) {
			$seek_result[ $kind ] = 'no-bookmark';
			continue;
		}
		$seek_result[ $kind ] = array(
			'ok'      => $s->seek( 'target' ),
			'before'  => $marked,
			'after'   => $s->get_breadcrumbs(),
			'tag'     => $s->get_tag(),
			'error'   => $s->get_last_error(),
		);
	}

	// ── Mutation trace (BR-MIGRATE-220 / 221 / 222) ────────────────────────────
	$m = new WP_HTML_Tag_Processor( $html );
	$i = 0;
	$prefixes = array();
	$guard = 0;
	while ( $m->next_tag() && ++$guard < 2000 ) {
		++$i;
		if ( 1 === $i ) {
			$m->set_bookmark( 'first' );
		}
		$m->set_attribute( 'data-n', (string) $i );
		$m->add_class( 'c' . ( $i % 3 ) );
		if ( 0 === $i % 2 ) {
			$m->remove_class( 'c1' );
			$m->remove_attribute( 'id' );
		}
		$prefixes[] = $m->get_attribute_names_with_prefix( 'data-' );
	}
	if ( $m->has_bookmark( 'first' ) && $m->seek( 'first' ) ) {
		$m->set_attribute( 'data-seek', 'yes' );
		$m->remove_attribute( 'data-n' );
	}
	$mutated = base64_encode( $m->get_updated_html() );

	$results[] = array(
		'tags'     => $tag_trace,
		'paused'   => $tag_paused,
		'tree'     => $tree_trace,
		'error'    => $error,
		'message'  => $message,
		'mutated'  => $mutated,
		'prefixes' => $prefixes,
		'full'     => $full_trace,
		'full_error'   => $full_error,
		'full_message' => $full_message,
		'seek'     => $seek_result,
	);
}

echo json_encode( $results );
