<?php
/**
 * Reference oracle instance — WordPress 7.2-alpha-63330.
 * AD-08: this is not test tooling, it is the executable definition of the 363 rules.
 * RISK-002 residual: this database is READ-ONLY to the rebuild. Never a write target.
 */
define( 'DB_NAME', 'wp_oracle' );
define( 'DB_USER', 'wporacle' );
define( 'DB_PASSWORD', 'oracle' );
define( 'DB_HOST', '127.0.0.1' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

define( 'AUTH_KEY',         'oracle-fixed-auth-key-for-reproducibility' );
define( 'SECURE_AUTH_KEY',  'oracle-fixed-secure-auth-key' );
define( 'LOGGED_IN_KEY',    'oracle-fixed-logged-in-key' );
define( 'NONCE_KEY',        'oracle-fixed-nonce-key' );
define( 'AUTH_SALT',        'oracle-fixed-auth-salt' );
define( 'SECURE_AUTH_SALT', 'oracle-fixed-secure-auth-salt' );
define( 'LOGGED_IN_SALT',   'oracle-fixed-logged-in-salt' );
define( 'NONCE_SALT',       'oracle-fixed-nonce-salt' );

$table_prefix = 'wp_';

define( 'WP_DEBUG', true );
define( 'WP_DEBUG_LOG', __DIR__ . '/wp-content/debug.log' );
define( 'WP_DEBUG_DISPLAY', false );
define( 'WP_HOME', 'http://127.0.0.1:8099' );
define( 'WP_SITEURL', 'http://127.0.0.1:8099' );
define( 'DISABLE_WP_CRON', true );
define( 'AUTOMATIC_UPDATER_DISABLED', true );
define( 'WP_HTTP_BLOCK_EXTERNAL', true );

if ( ! defined( 'ABSPATH' ) ) { define( 'ABSPATH', __DIR__ . '/' ); }
require_once ABSPATH . 'wp-settings.php';
