# Changelog

Newest first.  Dates are release dates.

## Unreleased

### Added

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
