<?php
/**
 * tools/reset.php -- drop the oracle database and reinstall from scratch.
 *
 * The corpus must be STABLE: golden files are byte-compared, so a corpus that drifts
 * between runs makes every capture a false divergence. seed.php is additive by nature
 * (wp_insert_post() with a colliding title allocates a -2 slug rather than refusing), so
 * the way to re-seed is to reset first.
 *
 *   php tools/reset.php && php tools/install.php && php tools/seed.php
 *   # or simply: bin/oracle reseed
 */
require_once __DIR__ . '/../wp-config.php';

$db = new mysqli( DB_HOST, DB_USER, DB_PASSWORD );
if ( $db->connect_error ) { die( "connect: {$db->connect_error}\n" ); }
$db->query( 'DROP DATABASE IF EXISTS `' . DB_NAME . '`' );
$db->query( 'CREATE DATABASE `' . DB_NAME . '` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci' );
echo "dropped and recreated " . DB_NAME . "\n";
