# FreeBSD 15.1 base — traceability

- Upstream repo (official):   https://git.FreeBSD.org/src.git
- Mirror used here (egress):  https://github.com/freebsd/freebsd-src  (git.FreeBSD.org is 403 behind this environment's proxy; the GitHub mirror is bit-identical)
- Branch:                     releng/15.1
- Pinned commit:              e38a7085f3a8ecd317c947591fe42b5ca9ab317b
- Vendored subset:            freebsd/src-pinned/ holds the release tooling
                              (release/), the installer (usr.sbin/bsdinstall) and
                              rc (libexec/rc) — the exact parts CopperBSD
                              integrates with, at the pinned commit.
- Full tree:                  fetched at build time at the SAME commit by
                              build/fetch-src.sh (the whole src tree is ~1.5 GB;
                              pinning the commit keeps it reproducible rather than
                              vendoring gigabytes).
