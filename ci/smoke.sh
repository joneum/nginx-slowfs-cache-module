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
# It also covers two things that were wrong for as long: the answer
# lost its ETag as soon as the module was switched on, and the default
# temporary area was a bare /tmp, whose level directories are shared
# with the rest of the machine.
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

    # no slowfs_temp_path: the default has to land below the prefix
    slowfs_cache_path $WORK/cache levels=1:2 keys_zone=smoke:4m inactive=1h;

    server {
        listen 127.0.0.1:$PORT;

        location / {
            root $WORK/origin;

            slowfs_cache       smoke;
            slowfs_cache_key   \$uri;
            slowfs_cache_valid 1h;

            add_header X-Cache-Status \$slowfs_cache_status;
        }

        # the same file without the cache, to compare the ETag against
        location /plain/ {
            alias $WORK/origin/;
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
cached=$(find "$WORK/cache" -type f 2>/dev/null)
if [ -n "$cached" ]; then
	echo "$cached" | sed 's/^/  /'
else
	echo "  nothing was written" >&2
	fail=1
fi

echo "--- the temporary area is below the prefix, not in /tmp ---"
if [ -d "$WORK/slowfs_temp" ]; then
	echo "  $WORK/slowfs_temp"
else
	echo "  $WORK/slowfs_temp was never created" >&2
	fail=1
fi

echo "--- the ETag survives the cache ---"
etag_plain=$(curl -sI "http://127.0.0.1:$PORT/plain/file.txt" |
	tr -d '\r' | sed -n 's/^[Ee][Tt][Aa][Gg]: //p')
etag_cache=$(curl -sI "http://127.0.0.1:$PORT/file.txt" |
	tr -d '\r' | sed -n 's/^[Ee][Tt][Aa][Gg]: //p')
if [ -z "$etag_cache" ]; then
	echo "  the cached answer carries no ETag" >&2
	fail=1
elif [ "$etag_plain" != "$etag_cache" ]; then
	echo "  without the cache $etag_plain, through it $etag_cache" >&2
	fail=1
else
	echo "  $etag_cache, the same one the static handler produces"
fi

echo "--- a conditional request is answered with 304 ---"
if [ -n "$etag_cache" ]; then
	code=$(curl -s -o /dev/null -w '%{http_code}' \
		-H "If-None-Match: $etag_cache" \
		"http://127.0.0.1:$PORT/file.txt") || code=000
	if [ "$code" = 304 ]; then
		echo "  304"
	else
		echo "  HTTP $code, expected 304" >&2
		fail=1
	fi
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
