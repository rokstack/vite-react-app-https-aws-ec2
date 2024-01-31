#!/bin/sh
echo "Starting Nginx..."
echo $PATH
which nginx
exec nginx -g 'daemon off;'