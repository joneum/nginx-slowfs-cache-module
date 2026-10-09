# Changelog

Newest first.  Dates are release dates.

## 1.12 (2026-10-09)

### Changed

- The bounded apt call moved out of `.github/actions/setup` and into
  `ci/apt-get.sh`, and the lint workflow now uses it instead of carrying a
  second, unbounded copy.  Two things follow.  There is one implementation
  of the bound and the retries rather than two that can drift apart, and
  shellcheck actually sees it: the `shell` job checks every script under
  `ci/`, while a `run:` block inside a workflow is invisible to it.
- The lint workflow no longer installs shellcheck unconditionally.  The
  runner image ships it, so the step only acts if that ever stops being
  true -- and then through the same wrapper, because a stalled mirror must
  not hold this job either.
- The widened gate earned its keep on the spot: a comment in the new
  script began with `# shellcheck`, which shellcheck reads as a directive
  and then cannot parse -- SC1072 and SC1073, both errors.  The sentence is
  reworded.  That line sat in a `run:` block before the move and nothing
  would ever have looked at it.
- The repository moved from `joneum` to the `sysadmin-labs` organization.
  Badges and links in the README point to the new address; the old URLs
  redirect.

### Added

- A hostile-client test: `ci/hostile.sh` and a workflow of its own.  The
  rest here drives one request at a time -- `t/small_file.t`,
  `t/big_file.t` and `ci/smoke.sh` all fetch, compare, fetch again -- and
  the more interesting half of this module cannot be reached that way.  For
  a file of at least `slowfs_big_file_size`, 131072 by default, it does not
  copy into the cache in the worker at all: it forks a child, renames it in
  the process table, lets the child write the entry, and serves the client
  from the source meanwhile.  A fork per request is where concurrency and
  aborts hurt.
- Five cases, all above that threshold so every one takes the forking path:
  one client as a reference, ten clients at once on an entry that does not
  exist yet, a client that walks away while its child is still copying, a
  range request on a file that comes from the cache, and a source file that
  is deleted after it was cached.  The oracles are the full file byte for
  byte, exactly one cache entry after the ten -- not ten -- and no child
  process left behind afterwards.
- The range case is the one nothing else asked for.  `r->allow_ranges` is
  set on the cache path as well as on the source path, and until now only
  the source path was ever asked for a range.
- A cache entry outlives its source: within `slowfs_cache_valid` the answer
  comes from the entry and the source is not touched.  That is what a cache
  is for, and now it is written down.
- Proven against a planted defect, and the control is specific.  With
  `r->allow_ranges = 0` on the cache path only -- one line in
  `ngx_http_slowfs_cache_send` -- `ci/smoke.sh` stays green at exit 0 while
  `ci/hostile.sh` fails on exactly that case with "HTTP 200, expected 206".
  So the new check measures something the old ones do not.

- A reload test: `ci/reload.sh`, the per-module `ci/reload.conf` beside it,
  and a workflow of its own.  nginx is reloaded eight times in a row and
  after every one of them the module has to answer correctly, the worker
  generation has to be the new one and nothing of the old one left, the
  master's descriptor count has to be where it started, and no worker may
  have died by signal.  A module that allocates or opens something per cycle
  and never gives it back is invisible in normal use -- nothing fails,
  nothing is logged, and the process grows by one cycle's worth on every
  reload -- and a test suite cannot see it, because a suite starts nginx
  once.
- The probe asks the module, not the server.  A reload that left the module
  behind still answers 200, so the check is the value `let` computed, the
  field `set_form_input` read out of the body, the `Content-Encoding` header
  only this module can set, or the file that came through the cache.
- Deliberately no band on the master's resident size.  Measured here, a
  healthy series grows the master by about twenty-five pages per reload, the
  allocator keeping what it freed, while a leaked cycle pool is a handful of
  pages.  Any band wide enough not to flap is wider than the thing it would
  have to catch, so it could never fail for the right reason.  The descriptor
  count is sharp and needs no band.
- Proven against a planted leak before it was written down: one descriptor
  opened per configuration load inside the directive handler took the
  master's count from 10 to 18 over eight reloads and the check went red.

- Every archive the build downloads is now verified against a sha256
  recorded in `.github/versions.env`: the nginx release and the actionlint
  release archive, through the new `ci/fetch-verify.sh`.  A changed archive,
  a truncated download or a build cache somebody else filled now fails the
  build instead of being compiled.  A file that fails the check is removed
  so the next run cannot pick it up, and a file that is already present is
  hashed again rather than trusted.

### Fixed

- `ci/ubsan.suppress` names the one finding nginx's own startup produces on
  1.30.5: `ngx_pstrdup` copies a zero-length string from a null pointer while
  `ngx_init_cycle` sets up the prefixes, before a single module is loaded.
  The entry carries the full stack and the reason, and it comes out again as
  soon as the shipped stable line no longer carries it.  1.31.6 does not.

### Changed

- Every job now carries a `timeout-minutes`, and the apt step in
  `.github/actions/setup` is bounded with `timeout` and retried.  A mirror
  that accepted the connection and then stopped answering held six jobs in
  that step until GitHub's own six hour ceiling killed them -- 360 and 361
  minutes for two of them.  The run produced no verdict at all and spent
  about 36 hours of runner time doing it.  A step inside a composite action
  cannot carry `timeout-minutes`, hence the explicit `timeout` there.  The
  bounds are measured rather than guessed: across the four repositories the
  slowest healthy job is CodeQL at 2.8 minutes and every other one stays
  under 2.5, so 15 minutes leaves five times the headroom, with 20 for
  CodeQL and 25 for the job that boots a virtual machine.

- `valgrind.suppress` carries two entries instead of 7, and both say what
  they hide.  Measured, not assumed: with an empty file the suite reports
  exactly two things and nothing else, the environment array nginx keeps in
  `ngx_set_environment` and the connection and event arrays it keeps in
  `ngx_event_process_init`.  No invalid read, no uninitialised value, no
  conditional jump -- so everything beyond those two suppressed something
  that never happens.  The file is now the same in all four module
  repositories.
- Both traces run through `ngx_single_process_cycle`, because Test::Nginx
  starts nginx with `master_process off`.  An entry for the master's own path
  could never be reached from this suite, which is why there is none: a
  suppression nobody can check is worse than no suppression.

- The deep checks -- codeql, lint, sanitizers, valgrind and the FreeBSD run
  -- now build 1.30.5, the release `www/nginx`, `www/nginx-full` and
  `www/nginx-lite` ship, instead of mainline.  They used to look at a version
  no package carries.

- Versions live in `.github/versions.env` and nowhere else.  Every workflow
  and `ci/build.sh` read them from there, so a release bump is one edit in
  one file instead of one per workflow, and the digest moves with the
  version it belongs to.  `ci/build.sh` refuses a version it has no digest
  for rather than building it unverified.
- `.github/scripts/pins.sh` hands the release list to `build-test` as a job
  output, because a matrix is read before any step of its own job can run.

### Removed

- nginx 1.22.0, 1.24.0 and 1.26.3 are out of the test matrix.  nginx keeps
  only the current stable and the current mainline alive; everything below
  1.30 is archive material upstream, and no FreeBSD port of this module uses
  it.  The floor is now 1.28.3, the last release of the previous stable line,
  kept so a newer nginx interface cannot creep in unnoticed.

### Known gap

- `Test::Nginx` still comes from CPAN unpinned, installed by `cpanm` in the
  shared setup action.  Pinning it means choosing a version for the suite,
  which is a separate decision.
- The digests prove what we build against, not where it came from.
  nginx.org publishes a detached signature next to each archive; verifying
  it would need the signing keys in the workflow.

## 1.11 (2026-10-05)

- First release from this repository.
