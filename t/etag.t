# vi:filetype=perl

use lib 'lib';
use Test::Nginx::Socket 'no_plan';

repeat_each(1);

# no slowfs_temp_path here on purpose: this also covers the default,
# which has to land below the nginx prefix and not in a shared /tmp
our $http_config = <<'_EOC_';
    slowfs_cache_path  /tmp/ngx_slowfs_etag_cache keys_zone=etag_cache:10m;
_EOC_

our $config = <<'_EOC_';
    location /slowfs {
        alias               /etc;
        slowfs_cache        etag_cache;
        slowfs_cache_key    $uri$is_args$args;
        slowfs_cache_valid  3m;
        add_header          X-Cache-Status $slowfs_cache_status;
    }

    location /noetag {
        alias               /etc;
        etag                off;
        slowfs_cache        etag_cache;
        slowfs_cache_key    "noetag$uri$is_args$args";
        slowfs_cache_valid  3m;
    }
_EOC_

worker_connections(128);
no_shuffle();
run_tests();

no_diff();

__DATA__

=== TEST 1: a file served through the cache carries an ETag
--- http_config eval: $::http_config
--- config eval: $::config
--- request
GET /slowfs/passwd
--- error_code: 200
--- raw_response_headers_like: ETag: "[0-9a-f]+-[0-9a-f]+"
--- timeout: 10



=== TEST 2: the ETag is still there when the answer comes from the cache
--- http_config eval: $::http_config
--- config eval: $::config
--- request
GET /slowfs/passwd
--- error_code: 200
--- raw_response_headers_like: ETag: "[0-9a-f]+-[0-9a-f]+"
--- response_headers
X-Cache-Status: HIT
--- timeout: 10



=== TEST 3: etag off takes it away again
--- http_config eval: $::http_config
--- config eval: $::config
--- request
GET /noetag/passwd
--- error_code: 200
--- raw_response_headers_unlike: ETag
--- timeout: 10
