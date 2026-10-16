# Testing and verification

## Repeatable checks

```sh
nix flake check
nix develop -c cabal check
nix develop -c cabal build all --offline -fstrict
nix develop -c cabal test all --offline -fstrict --test-show-details=direct
nix develop -c cabal haddock all --offline
nix develop -c cabal sdist
```

The Nix package uses the Cabal file for its build, tests and documentation. Local
Cabal workflows use dependencies supplied by `nix develop`; no Hackage repository
is enabled by cabal.project. Cabal checks/source distributions require no live AMO.

## Coverage

Regression scenarios cover metadata parsing, permissions/licenses, GUID/slug
conflicts, user-range splitting, live count/page-hint drift, shrinking/empty/short
pages, late cap repartitioning, overlap deduplication, metadata updates, open upper
ranges and retention of observed records across splits, selected-request
abort behavior, JSONL Unicode/newlines, typed HTTP errors, retry budgets and
Retry-After, and atomic-file cleanup/preservation. Integration uses loopback HTTP
and an actual JSONL destination. Retry sleeps/clocks are injected for deterministic
checks; tests have a runner timeout. QuickCheck covers serialization framing,
canonicalization invariants and numeric Retry-After parsing.

Some inherited scenarios intentionally group related assertions in a single
regression case. Properties supplement those scenarios; a passing case count is
not a claim of exhaustive behavior coverage. Loopback socket tests require a
sandbox that permits local sockets, but no external network access.

## Packaging notes

`cabal check` currently reports only a missing `source-repository` warning: this
local project has no published remote URL yet. Do not invent one to suppress it.
Haddock builds project documentation but may warn about missing external
attoparsec/vector documentation links in the pinned Nix package set. Offline Cabal
can warn about a missing Hackage index even though this project resolves its
installed Nix dependencies without fetching packages.

## Live checks (explicit, not part of test suite)

```sh
nix run . -- selected selected.jsonl ublock-origin keepassxc-browser
nix run . -- discover popular.jsonl 100000
```

The earlier implementation successfully fetched 111 records over three live pages
at that threshold and preserved old output on a failed detail request. Those counts
are historical observations, not fixed expected values for future live API tests.
The full default crawl has not been verified. aarch64-linux outputs are declared
but not runtime-tested. Packaging/layout changes must not be reported as full live
crawler verification.
