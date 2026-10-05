Upstream reports
================

Everything that is open at
[FRiCKLE/ngx_slowfs_cache](https://github.com/FRiCKLE/ngx_slowfs_cache),
and where this fork stands on it.  Upstream has taken no change since
2013.

Fixed here
----------

| | | |
|---|---|---|
| [#11](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/11), [#12](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/12) | nginx dies while reading a configuration that carries `slowfs_cache_path` | `slowfs_cache_path` handed `ngx_http_file_cache_set_slot()` a null configuration, because nginx had moved from one global list of caches to a per-module array. The module has a main configuration with a `caches` array now, and `ci/smoke.sh` reads such a configuration and starts nginx on every push. |
| [#9](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/9) | the module ignores ETag | A file served through the cache lost the header that the static handler puts on it. It carries the same ETag now, and a conditional request is answered with 304. `t/etag.t` and `ci/smoke.sh` guard it. |
| [PR #13](https://github.com/FRiCKLE/ngx_slowfs_cache/pull/13) | build as a dynamic module | Works, and the workflow builds it as a loadable object on every push. |

Not reproduced
--------------

Measured against nginx 1.31.6 on FreeBSD, one request per measurement.

| | | |
|---|---|---|
| [#7](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/7) | `$slowfs_cache_status` is almost always HIT | MISS on the first request for a file, HIT on every one after it. |
| [#3](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/3) | does not work together with `open_file_cache` | With `open_file_cache` switched on the status goes MISS, HIT, HIT, HIT and the body matches the file on disk byte for byte, the same as without it. |
| [#8](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/8) | `max_size` is not honoured | Twenty files of 200 KB through a cache limited to 1 MB: the cache manager trims it back to five files and holds there. The 1088 KB that `du` reports against a limit of 1024 KB is the level directories. |
| [#5](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/5) | crash when `cache->file.name` is not populated | No case that reaches it. The report proposes a guard but names no configuration or request that gets there, and nothing in the suite or the smoke run produces it. Left alone rather than adding a condition whose effect cannot be shown. |

Nothing to do
-------------

| | | |
|---|---|---|
| [#10](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/10), [#2](https://github.com/FRiCKLE/ngx_slowfs_cache/issues/2) | how to warm the cache without answering the client, still many RPC calls against NFS | Questions about using the module. |

Changed here without an upstream report
---------------------------------------

The temporary area used to default to a bare `/tmp`, whose level
directories are shared with everything else on the machine.  An
unrelated file named `1` in `/tmp` was enough to make every copy into the
cache fail with *Not a directory*, with nothing but an alert in the error
log to show for it.  It defaults to `slowfs_temp` below the nginx prefix
now, the way nginx places `client_body_temp` and `proxy_temp`.
`ci/smoke.sh` checks where it lands.
