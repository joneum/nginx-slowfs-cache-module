#!/bin/sh
#
# Build an nginx that carries this module.  The continuous integration
# workflow runs this, and so can you:
#
#     ci/build.sh 1.31.6 /tmp/nginx-test
#     TEST_NGINX_BINARY=/tmp/nginx-test/sbin/nginx prove -r t/
#
# usage: ci/build.sh <nginx version> <install prefix> [mode]
#
#     static    the module built into the binary (the default)
#     dynamic   the module built as a loadable object
#
# nginx lands in $CI_WORK, ./ci-work by default, and is reused on a
# second run.  A warning from this module's own source fails the build.

set -eu

NGINX=${1:?nginx version missing}
PREFIX=${2:?install prefix missing}
MODE=${3:-static}

SRC=$(cd "$(dirname "$0")/.." && pwd)
WORK=${CI_WORK:-$SRC/ci-work}
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)

mkdir -p "$WORK"

tarball=$WORK/nginx-$NGINX.tar.gz
url=https://nginx.org/download/nginx-$NGINX.tar.gz

if [ ! -s "$tarball" ]; then
	# curl is a package on FreeBSD, fetch is in the base system
	if command -v curl > /dev/null 2>&1; then
		curl -sSfL -o "$tarball" "$url"
	else
		fetch -q -o "$tarball" "$url"
	fi
fi

rm -rf "$WORK/nginx-$NGINX"
tar xzf "$tarball" -C "$WORK"

case $MODE in
static)
	how=--add-module
	;;
dynamic)
	how=--add-dynamic-module
	;;
*)
	echo "ci/build.sh: unknown mode \"$MODE\"" >&2
	exit 2
	;;
esac

cd "$WORK/nginx-$NGINX"

# the module stores what it fetched in nginx's file cache, so the cache
# has to be in the build: --with-http_ssl_module brings the proxy module
# along, and with it NGX_HTTP_CACHE

echo "--- configure ($MODE) ---"
./configure --prefix="$PREFIX" --with-debug --with-http_ssl_module \
	"$how=$SRC" > "$WORK/configure-$NGINX.log" 2>&1 ||
	{ tail -30 "$WORK/configure-$NGINX.log"; exit 1; }

echo "--- make -j$JOBS ---"
make -j"$JOBS" > "$WORK/make-$NGINX.log" 2>&1 ||
	{ tail -40 "$WORK/make-$NGINX.log"; exit 1; }

if grep -E "ngx_http_slowfs_module\.c.*warning" "$WORK/make-$NGINX.log"; then
	echo "ci/build.sh: the compiler warned about this module, see above" >&2
	exit 1
fi

make install > /dev/null
"$PREFIX/sbin/nginx" -v
