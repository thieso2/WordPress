<?php
define('WP_INSTALLING', true);
$_SERVER['HTTP_HOST']   = 'oracle.local';
$_SERVER['REQUEST_URI'] = '/wp-admin/install.php';
$_SERVER['SERVER_NAME'] = 'oracle.local';
$_SERVER['REQUEST_METHOD'] = 'GET';
require_once "/workspace/WordPress/_reversa_forward/oracle/wordpress/wp-load.php";
require_once ABSPATH . 'wp-admin/includes/upgrade.php';
if ( is_blog_installed() ) { echo "ALREADY INSTALLED\n"; exit(0); }
$r = wp_install( 'Reversa Oracle', 'oracle_admin', 'oracle@example.com', true, '', 'oracle-admin-pw' );
echo "INSTALLED user_id=" . $r['user_id'] . "\n";
