<?php
// Router for PHP's built-in server so pretty permalinks resolve, matching the
// permalink_structure the corpus is seeded with (/%year%/%monthnum%/%postname%/).
$path = parse_url( $_SERVER['REQUEST_URI'], PHP_URL_PATH );
$file = __DIR__ . $path;
if ( $path !== '/' && file_exists( $file ) && ! is_dir( $file ) ) {
    if ( substr( $file, -4 ) === '.php' ) { require $file; return true; }
    return false; // let the server stream static assets
}
if ( is_dir( $file ) && file_exists( rtrim( $file, '/' ) . '/index.php' ) ) {
    require rtrim( $file, '/' ) . '/index.php';
    return true;
}
require __DIR__ . '/index.php';
return true;
