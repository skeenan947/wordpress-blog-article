<?php

/**
 * The base configurations of the WordPress.
 *
 * This file has the following configurations: MySQL settings, Table Prefix,
 * Secret Keys, WordPress Language, and ABSPATH. You can find more information by
 * visiting {@link http://codex.wordpress.org/Editing_wp-config.php Editing
 * wp-config.php} Codex page. You can get the MySQL settings from your web host.
 *
 * This file is used by the wp-config.php creation script during the
 * installation. You don't have to use the web site, you can just copy this file
 * to "wp-config.php" and fill in the values.
 *
 * @package WordPress
 */

define('WP_DEBUG', filter_var(getenv('WP_DEBUG'), FILTER_VALIDATE_BOOLEAN));
if (filter_var(getenv('WP_DEBUG'), FILTER_VALIDATE_BOOLEAN)) {
    define('WP_DEBUG_LOG', '/dev/stderr');
    define('WP_DEBUG_DISPLAY', false);
}
define('WP_HOME', getenv('WP_BASEURL'));
define('WP_SITEURL', getenv('WP_BASEURL'));

# Ensure proper HTTPS detection behind Cloud Run since Cloud Run terminates SSL
if (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}

define('FORCE_SSL_LOGIN', false);
define('FORCE_SSL_ADMIN', false);

// ** MySQL settings - You can get this info from your web host ** //

// use connection pooling
define('USE_PCONNECT', true);
define('WP_CACHE', false);

/** The name of the database for WordPress */
define('DB_NAME', getenv('DB_NAME'));

/** MySQL database username */
define('DB_USER', getenv('DB_USER'));

/** MySQL database login */
define('DB_HOST', getenv('DB_HOST'));
define('DB_PASSWORD', getenv('DB_PASS'));

/** Database Charset to use in creating database tables. */
define('DB_CHARSET', 'utf8');

/** The Database Collate type. Don't change this if in doubt. */
define('DB_COLLATE', '');

/**#@+
 * Authentication Unique Keys.
 *
 * Change these to different unique phrases!
 * You can generate these using the {@link https://api.wordpress.org/secret-key/1.1/ WordPress.org secret-key service}
 * You can change these at any point in time to invalidate all existing cookies. This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define('AUTH_KEY',        'wUVB[~ZEZ[,X-.<UgH!63-|p,bm1N1>{zP@8m.ttJp-4qya!<?!$:65t1KsD#LI*');
define('SECURE_AUTH_KEY', '%bL$rC?y:9r!-.38qs|46ZRSW tPYLhv_wn9|)<Nd!T|7?Wv[{^^&xuX:ok7Y!G)');
define('LOGGED_IN_KEY',   '2?,F$zfy>k;6+@>ic.FD$r~+JmDf.2<jm$CSP S1UB+V-F<XeH+Zz^Q+d3bWf}`?');
define('NONCE_KEY',       'feC5*M2tdH06ss/-78|nOw*%T6-/|pov_0 iMSKS+Yrh$|f1pDz.UU]!=ouxt+t*');
/**#@-*/

/**
 * WordPress Database Table prefix.
 *
 * You can have multiple installations in one database if you give each a unique
 * prefix. Only numbers, letters, and underscores please!
 */
$table_prefix  = 'wp_';

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the documentation.
 *
 * @link https://wordpress.org/support/article/debugging-in-wordpress/
 */
define( 'WP_DEBUG', false );

/* Add any custom values between this line and the "stop editing" line. */



/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
?>