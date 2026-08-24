<?php
// Dumps the admin menu exactly as wp-admin builds it for a given user, so the rebuild's
// declared navigation (DEV-002) can be authored against observed truth rather than guessed
// from menu.php's runtime-generated arrays.
define( 'WP_ADMIN', true );
$_SERVER['REQUEST_URI'] = '/wp-admin/index.php';
require dirname( __DIR__ ) . '/wp-load.php';
require_once ABSPATH . 'wp-admin/includes/admin.php';

$login = $argv[1] ?? 'oracle_admin';
$u = get_user_by( 'login', $login );
if ( ! $u ) { fwrite( STDERR, "no user $login\n" ); exit( 1 ); }
wp_set_current_user( $u->ID );

require ABSPATH . 'wp-admin/menu.php';

$out = array();
foreach ( $menu as $pos => $item ) {
    if ( empty( $item[0] ) && strpos( (string) ( $item[4] ?? '' ), 'separator' ) !== false ) {
        $out[] = array( 'pos' => $pos, 'separator' => true );
        continue;
    }
    $slug = $item[2];
    $subs = array();
    if ( ! empty( $submenu[ $slug ] ) ) {
        foreach ( $submenu[ $slug ] as $spos => $s ) {
            $subs[] = array( 'pos' => $spos, 'title' => wp_strip_all_tags( $s[0] ), 'cap' => $s[1], 'slug' => $s[2] );
        }
    }
    $out[] = array(
        'pos'   => $pos,
        'title' => wp_strip_all_tags( $item[0] ),
        'cap'   => $item[1],
        'slug'  => $slug,
        'icon'  => $item[6] ?? '',
        'subs'  => $subs,
    );
}
echo json_encode( $out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE ), "\n";
