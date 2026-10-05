#!/bin/sh
#
# Read a configuration that carries slowfs_cache_path, start nginx and
# fetch a file through the cache.
#
# For about ten years a single slowfs_cache_path was enough to kill
# nginx while it was still reading the configuration: the directive
# handed ngx_http_file_cache_set_slot() a null configuration, and that
# function pushes onto an array it finds there.  Nobody noticed, because
# nothing ever built and started this module.  That is what this guards.
#
# usage: ci/smoke.sh <nginx binary>
#
# Set SMOKE_LOAD_MODULE to the path of ngx_http_slowfs_module.so to test
# a loadable build.

set -eu

NGINX=${1:?path to the nginx binary missing}
WORK=${CI_WORK:-$(cd "$(dirname "$0")/.." && pwd)/ci-work}/smoke
PORT=${SMOKE_PORT:-18100}

command -v curl > /dev/null || { echo "curl(1) is needed" >&2; exit 2; }

rm -rf "$WORK"
mkdir -p "$WORK/conf" "$WORK/logs" "$WORK/cache" "$WORK/origin"

# something long enough to be worth caching, and compressible so a
# mistake in the copy shows up in the comparison
i=0
while [ $i -lt 200 ]; do
	echo "line $i of the file that lives on the slow filesystem"
	i=$((i + 1))
done > "$WORK/origin/file.txt"

ngx_user=
if [ "$(id -u)" = 0 ]; then
	ngx_user="user root $(id -gn);"
fi

ngx_load=
if [ -n "${SMOKE_LOAD_MODULE:-}" ]; then
	ngx_load="load_module $SMOKE_LOAD_MODULE;"
fi

cat > "$WORK/conf/nginx.conf" <<EOF
$ngx_load
$ngx_user
worker_processes 1;
error_log $WORK/logs/error.log error;
pid $WORK/logs/nginx.pid;
events { worker_connections 64; }
http {
    access_log off;

    slowfs_cache_path $WORK/cache levels=1:2 keys_zone=smoke:4m inactive=1h;
    slowfs_temp_path  $WORK/cache/tmp;

    server {
        listen 127.0.0.1:$PORT;

        location / {
            root $WORK/origin;

            slowfs_cache       smoke;
            slowfs_cache_key   \$uri;
            slowfs_cache_valid 1h;

            add_header X-Cache-Status \$slowfs_cache_status;
        }
    }
}
EOF

echo "--- the configuration is read without dying ---"
"$NGINX" -p "$WORK" -c conf/nginx.conf -t

"$NGINX" -p "$WORK" -c conf/nginx.conf

stop() {
	[ -s "$WORK/logs/nginx.pid" ] && kill "$(cat "$WORK/logs/nginx.pid")" 2> /dev/null
	return 0
}
trap stop EXIT

sleep 1

echo "--- the file comes back unchanged ---"
fail=0
for n in 1 2 3; do
	status=$(curl -s -o "$WORK/body" -w '%{http_code}' \
		"http://127.0.0.1:$PORT/file.txt") || status=000

	if [ "$status" != 200 ]; then
		echo "  request $n: HTTP $status"
		fail=1
		continue
	fi

	if cmp -s "$WORK/origin/file.txt" "$WORK/body"; then
		echo "  request $n: HTTP 200, identical"
	else
		echo "  request $n: HTTP 200, but the body differs"
		fail=1
	fi
	sleep 1
done

echo "--- something reached the cache ---"
# the temporary directory sits inside the cache directory, so leave it
# out by its full path; a pattern like */tmp/* would also match every
# work tree that happens to live under /tmp
cached=$(find "$WORK/cache" -type f ! -path "$WORK/cache/tmp/*" 2>/dev/null)
if [ -n "$cached" ]; then
	echo "$cached" | sed 's/^/  /'
else
	echo "  nothing was written" >&2
	fail=1
fi

echo "--- nginx is still running ---"
if kill -0 "$(cat "$WORK/logs/nginx.pid")" 2> /dev/null; then
	echo "  yes"
else
	echo "  no, it died" >&2
	fail=1
fi

if grep -qE '\[alert\]|\[crit\]|\[emerg\]' "$WORK/logs/error.log" 2> /dev/null; then
	echo "--- the error log complains ---" >&2
	grep -E '\[alert\]|\[crit\]|\[emerg\]' "$WORK/logs/error.log" | head -5 >&2
	fail=1
fi

[ "$fail" -eq 0 ]
