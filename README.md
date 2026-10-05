About
=====
`ngx_slowfs_cache` is `nginx` module which allows caching of static files
(served using `root` directive). This enables one to create fast caches
for files stored on slow filesystems, for example:

- storage: network disks, cache: local disks,
- storage: 7,2K SATA drives, cache: 15K SAS drives in RAID0.


**WARNING! There is no point in using this module when cache is placed
on the same speed disk(s) as origin.**


Sponsors
========
`ngx_slowfs_cache` was fully funded by [c2hosting.com](http://c2hosting.com).


Status
======
In use again.  The module builds against nginx 1.22.0, 1.24.0, 1.26.3,
1.28.0, 1.30.5 and 1.31.6, and on each of them a configuration that
carries `slowfs_cache_path` is read, nginx starts and a file comes back
through the cache with its ETag on it.  That is checked on Linux and on
FreeBSD in [continuous
integration](https://github.com/joneum/nginx-slowfs-cache-module/actions).

Between roughly nginx 1.7.12 and this fork the module could not be used
at all: `slowfs_cache_path` handed `ngx_http_file_cache_set_slot()` a
null configuration, because nginx had moved from one global list of
caches to a per-module array, and nginx died while reading the
configuration.  Two reports of exactly that went unanswered upstream,
[#11](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/11) from
FreeBSD and [#12](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/12)
from CentOS, both in 2015 against nginx 1.8.0.

The old list of releases this section used to carry, 0.7 through 1.3,
described a state of affairs that ended more than ten years ago.


Configuration notes
===================
`slowfs_cache_path` and `slowfs_temp_path` values should point to the same
filesystem, otherwise files will be copied twice.

The temporary area defaults to `slowfs_temp` below the nginx prefix,
the way nginx places `client_body_temp` and `proxy_temp`.  Upstream
used a bare `/tmp`, which shares its level directories with everything
else on the machine; a stray file named `1` in `/tmp` was enough to
make every copy into the cache fail.

`ngx_slowfs_cache` currently doesn't work when AIO is enabled.


Configuration directives
========================
slowfs_cache
------------
* **syntax**: `slowfs_cache zone_name`
* **default**: `none`
* **context**: `http`, `server`, `location`

Sets area used for caching (previously definied using `slowfs_cache_path`).
  

slowfs_cache_key
----------------
* **syntax**: `slowfs_cache_key key`
* **default**: `none`
* **context**: `http`, `server`, `location`

Sets key for caching.


slowfs_cache_purge
------------------
* **syntax**: `slowfs_cache_purge zone_name key`
* **default**: `none`
* **context**: `location`

Sets area and key used for purging selected pages from cache.


slowfs_cache_path
-----------------
* **syntax**: `slowfs_cache_path path [levels] keys_zone=zone_name:zone_size [inactive] [max_size]`
* **default**: `none`
* **context**: `http`

Sets cache area and its structure.


slowfs_temp_path
----------------
* **syntax**: `slowfs_temp_path path [level1] [level2] [level3]`
* **default**: `slowfs_temp 1 2`
* **context**: `http`
  
Sets temporary area where files are stored before they are moved to cache area.


slowfs_cache_min_uses
---------------------
* **syntax**: `slowfs_cache_min_uses number`
* **default**: `1`
* **context**: `http`, `server`, `location`

Sets number of uses after which file is copied to cache.


slowfs_cache_valid
------------------
* **syntax**: `slowfs_cache_valid [reply_code] time`
* **default**: `none`
* **context**: `http`, `server`, `location`

Sets time for which file will be served from cache.


slowfs_big_file_size
--------------------
* **syntax**: `slowfs_big_file_size size`
* **default**: `128k`
* **context**: `http`, `server`, `location`

Sets minimum file size for `big` files. Worker processes `fork()` child process
before they start copying `big` files to avoid any service disruption. 


Configuration variables
=======================
$slowfs_cache_status
--------------------
Represents availability of cached file.

Possible values are: `MISS`, `HIT` and `EXPIRED`.


Sample configuration
====================
    http {
        slowfs_cache_path  /tmp/cache levels=1:2 keys_zone=fastcache:10m;
        slowfs_temp_path   /tmp/temp 1 2;

        server {
            location / {
                root                /var/www;
                slowfs_cache        fastcache;
                slowfs_cache_key    $uri;
                slowfs_cache_valid  1d;
            }

            location ~ /purge(/.*) {
                allow               127.0.0.1;
                deny                all;
                slowfs_cache_purge  fastcache $1;
            }
       }
    }

Testing
=======
`ngx_slowfs_cache` comes with complete test suite based on [Test::Nginx](http://github.com/agentzh/test-nginx).

You can test it by running:

`$ prove`


License
=======
    Copyright (c) 2009-2012, FRiCKLE <info@frickle.com>
    Copyright (c) 2009-2012, Piotr Sikora <piotr.sikora@frickle.com>
    Copyrithg (c) 2002-2012, Igor Sysoev <igor@sysoev.ru>
    All rights reserved.

    This project was fully funded by c2hosting.com.
    Included cache_purge functionality was fully funded by yo.se.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
    A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
    HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
    LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


See also
========
- [ngx_cache_purge](http://github.com/FRiCKLE/ngx_cache_purge).
