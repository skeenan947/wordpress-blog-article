#!/usr/bin/env bash

echo test
if [ -z "${WP_NFS_SERVER}" -o -z "${WP_NFS_SHARE}" ]
then
  echo "Running WordPress without NFS mount.  To mount NFS, set WP_NFS_SERVER and WP_NFS_SHARE"
else
  rpc.statd & rpcbind -f & echo "docker NFS client with rpcbind ENABLED..."
  # Wait a moment for rpcbind to start up before trying to mount
  sleep 1
  NFS_FLAGS="-o nolock,nfsvers=${WP_NFS_VERSION-3}"
  echo mounting NFS with: mount ${NFS_FLAGS} "${WP_NFS_SERVER}:${WP_NFS_SHARE}" /var/www/html
  if ! (mount ${NFS_FLAGS} "${WP_NFS_SERVER}:${WP_NFS_SHARE}" /var/www/html); then
    echo "Failed to mount NFS, exiting"
    exit 1
  fi
  sleep 1
fi

# make sure we cd into the actual nfs, not the local directory under it
cd / && cd /var/www/html
# This entrypoint script is provided by the WordPress image
docker-entrypoint.sh apache2-foreground &
# Wait a second for Apache to start, then start pulling logs out for GCP Logging
sleep 1
# copy our wp-config.php into the wordpress dir
cp /var/www-local/core/wp-config.php /var/www/html/wp-config.php
tail -f /var/log/apache2/*