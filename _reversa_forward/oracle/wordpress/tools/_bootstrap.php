<?php
/** Shared CLI bootstrap for the oracle instance. */
if ( php_sapi_name() !== 'cli' ) { die( 'CLI only' ); }
$_SERVER['HTTP_HOST']      = 'oracle.local';
$_SERVER['SERVER_NAME']    = 'oracle.local';
$_SERVER['REQUEST_URI']    = '/';
$_SERVER['REQUEST_METHOD'] = 'GET';
$_SERVER['SERVER_PORT']    = '80';
require_once '/workspace/WordPress/_reversa_forward/oracle/wordpress/wp-load.php';
require_once ABSPATH . 'wp-admin/includes/admin.php';
