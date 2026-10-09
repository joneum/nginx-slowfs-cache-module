#!/bin/sh
#
# Put the module in front of clients that arrive together and walk away.
#
# Everything else here drives one request at a time: t/small_file.t,
# t/big_file.t and ci/smoke.sh all fetch, compare, fetch again.  The
# interesting half of this module is not reachable that way, because for a
# file of at least slowfs_big_file_size -- 131072 by default -- it does not
# copy into the cache in the worker at all.  It forks a child, renames it in
# the process table, lets the child write the cache entry, and serves the
# client from the source meanwhile.
#
# A fork per request is where concurrency and aborts hurt: several children
# can be writing the same entry at once, and the client the parent is
# serving can disappear while its child is still copying.  Neither can
# happen with one sequential client.
#
# usage: ci/hostile.sh <nginx binary>
#
# Set HOSTILE_LOAD_MODULE to the path of ngx_http_slowfs_module.so to test a
# loadable build, as ci/smoke.sh does.

set -eu

NGINX=${1:?path to the nginx binary missing}
WORK=${CI_WORK:-$(cd "$(dirname "$0")/.." && pwd)/ci-work}/hostile
PORT=${HOSTILE_PORT:-18500}

command -v curl > /dev/null || { echo "curl(1) is needed" >&2; exit 2; }
command -v awk > /dev/null || { echo "awk(1) is needed" >&2; exit 2; }

rm -rf "$WORK"
mkdir -p "$WORK/conf" "$WORK/logs" "$WORK/cache" "$WORK/origin" "$WORK/out"

fail=0
note() {
	echo "  $1" >&2
	fail=1
}

# Well over the default slowfs_big_file_size, so every one of these takes
# the forking path.  Numbered lines, so a copy that loses or duplicates a
# stretch shows up in cmp and not only in the size.
make_big() {
	awk -v n=20000 'BEGIN {
		for (i = 0; i < n; i++)
			printf "line %06d of the file that lives on the slow filesystem\n", i
	}' > "$1"
}

# One file per case that has to start uncached: the cache key is the uri, so
# a fresh name is a fresh entry.
for f in warm race abort vanish; do
	make_big "$WORK/origin/$f.bin"
done
size=$(wc -c < "$WORK/origin/warm.bin" | tr -d ' ')
echo "--- the files are above the forking threshold ---"
if [ "$size" -gt 131072 ]; then
	echo "  $size bytes each, slowfs_big_file_size defaults to 131072"
else
	note "$size bytes is not above 131072, the forking path is never taken"
fi

ngx_user=
if [ "$(id -u)" = 0 ]; then
	ngx_user="user root $(id -gn);"
fi

ngx_load=
if [ -n "${HOSTILE_LOAD_MODULE:-}" ]; then
	ngx_load="load_module $HOSTILE_LOAD_MODULE;"
fi

cat > "$WORK/conf/nginx.conf" <<EOF
$ngx_load
$ngx_user
worker_processes 1;
error_log $WORK/logs/error.log info;
pid $WORK/logs/nginx.pid;
events { worker_connections 64; }
http {
    access_log off;

    slowfs_cache_path $WORK/cache levels=1:2 keys_zone=hostile:4m inactive=1h;

    server {
        listen 127.0.0.1:$PORT;

        location / {
            root $WORK/origin;

            slowfs_cache       hostile;
            slowfs_cache_key   \$uri;
            slowfs_cache_valid 1h;

            add_header X-Cache-Status \$slowfs_cache_status;
        }
    }
}
EOF

echo "--- the configuration is read ---"
"$NGINX" -p "$WORK" -c conf/nginx.conf -t

"$NGINX" -p "$WORK" -c conf/nginx.conf

stop() {
	[ -s "$WORK/logs/nginx.pid" ] && kill "$(cat "$WORK/logs/nginx.pid")" 2> /dev/null
	return 0
}
trap stop EXIT
sleep 1

MASTER=$(cat "$WORK/logs/nginx.pid")

# Children of the master that are workers, by process title -- the copying
# children rename themselves, and the cache manager and loader are children
# too.
workers() {
	pgrep -P "$MASTER" -f 'worker process' 2> /dev/null | wc -l | tr -d ' '
}
children() {
	pgrep -P "$MASTER" 2> /dev/null | wc -l | tr -d ' '
}

entries() {
	find "$WORK/cache" -type f 2> /dev/null | wc -l | tr -d ' '
}

get() { # get <uri> <outfile> [extra curl args...]
	uri=$1
	outfile=$2
	shift 2
	curl -s --max-time 30 -o "$outfile" -w '%{http_code}' "$@" \
		"http://127.0.0.1:$PORT$uri" 2> /dev/null || true
}

settle() { # the copying child is on its own clock
	n=0
	while [ $n -lt 50 ]; do
		[ "$(children)" -le "$1" ] && return 0
		n=$((n + 1))
		sleep 0.1 2> /dev/null || sleep 1
	done
	return 1
}

base_children=$(children)

echo "--- one client, so the rest has a reference ---"
code=$(get /warm.bin "$WORK/out/warm")
if [ "$code" = 200 ] && cmp -s "$WORK/origin/warm.bin" "$WORK/out/warm"; then
	echo "  HTTP 200, identical"
else
	note "HTTP $code, and the body differs -- without this the rest means nothing"
fi

echo "--- ten clients at once on a file that is not cached yet ---"
# Ten forked children can be writing the same entry at the same time.  Each
# client has to get the whole file, and afterwards there has to be exactly
# one entry for it, not ten.
before=$(entries)
i=0
while [ $i -lt 10 ]; do
	get /race.bin "$WORK/out/race.$i" > "$WORK/out/code.$i" &
	i=$((i + 1))
done
wait
bad=0
i=0
while [ $i -lt 10 ]; do
	c=$(cat "$WORK/out/code.$i")
	if [ "$c" != 200 ]; then
		note "client $i: HTTP $c"
		bad=1
	elif ! cmp -s "$WORK/origin/race.bin" "$WORK/out/race.$i"; then
		note "client $i: HTTP 200 but the body differs"
		bad=1
	fi
	i=$((i + 1))
done
[ "$bad" -eq 0 ] && echo "  all ten got the whole file"
settle "$base_children" || note "a copying child is still around after 5 seconds"
added=$(( $(entries) - before ))
if [ "$added" = 1 ]; then
	echo "  and exactly one cache entry was written"
else
	note "ten clients left $added cache entries behind, expected 1"
fi

echo "--- a client that walks away while its child is still copying ---"
# The parent is sending from the source, a child is writing the cache entry.
# The client disappears in the middle.  The entry has to end up complete
# anyway, which the next request proves.
get /abort.bin "$WORK/out/abort.partial" --limit-rate 60k --max-time 1 \
	> /dev/null 2>&1 || true
if ! kill -0 "$MASTER" 2> /dev/null; then
	note "the master is gone"
fi
settle "$base_children" || note "a copying child is still around after 5 seconds"
code=$(get /abort.bin "$WORK/out/abort")
if [ "$code" = 200 ] && cmp -s "$WORK/origin/abort.bin" "$WORK/out/abort"; then
	echo "  the next request still gets the whole file"
else
	note "HTTP $code after the abort, and the body differs"
fi

echo "--- a range request on a file that comes from the cache ---"
# r->allow_ranges is set on the cache path as well as on the source path,
# so this has to be a 206 with exactly those bytes.  Nothing else here
# asks the cache for a range.
status=$(get /warm.bin "$WORK/out/range" -r 1000-1999)
dd if="$WORK/origin/warm.bin" of="$WORK/out/range.want" bs=1 skip=1000 \
	count=1000 2> /dev/null
if [ "$status" != 206 ]; then
	note "HTTP $status, expected 206"
elif cmp -s "$WORK/out/range.want" "$WORK/out/range"; then
	echo "  HTTP 206 with exactly the requested bytes"
else
	note "HTTP 206 but the bytes are not the ones that were asked for"
fi

echo "--- the source file is gone, the entry is not ---"
# What a cache is for: inside slowfs_cache_valid the answer comes from the
# entry and the source is not needed.
code=$(get /vanish.bin "$WORK/out/vanish.first")
if [ "$code" != 200 ]; then
	note "HTTP $code already on the first request"
fi
settle "$base_children" || note "a copying child is still around after 5 seconds"
cp "$WORK/origin/vanish.bin" "$WORK/out/vanish.want"
rm -f "$WORK/origin/vanish.bin"
code=$(get /vanish.bin "$WORK/out/vanish")
if [ "$code" = 200 ] && cmp -s "$WORK/out/vanish.want" "$WORK/out/vanish"; then
	echo "  HTTP 200 from the cache, identical to what the source held"
else
	note "HTTP $code once the source was removed, expected 200 from the cache"
fi

echo "--- nothing was left behind ---"
if [ "$(workers)" = 1 ] && [ "$(children)" -le "$base_children" ]; then
	echo "  one worker, no extra children"
else
	note "$(workers) workers and $(children) children, started with $base_children"
fi

echo "--- the worker survived all of it ---"
if kill -0 "$MASTER" 2> /dev/null; then
	echo "  yes"
else
	note "the master is gone"
fi

if grep -qE '\[alert\]|\[crit\]|\[emerg\]|exited on signal' "$WORK/logs/error.log" 2> /dev/null; then
	echo "--- the error log complains ---" >&2
	grep -E '\[alert\]|\[crit\]|\[emerg\]|exited on signal' "$WORK/logs/error.log" | head -5 >&2
	fail=1
fi

[ "$fail" -eq 0 ]
