# Changelog

## 0.1.0.0 — Unreleased

- Generate fresh JSONL for selected extensions or paginated AMO discovery.
- Partition oversized searches by daily-user range; abort rather than truncate.
- Tolerate live catalogue count/page drift instead of requiring frozen totals.
- Follow current page hints, repartition searches that grow past the cap, retain
  open upper ranges and already-observed records, and keep the last observed
  metadata per GUID. HTTP/metadata errors and final slug collisions still abort.
- Include permissions and nullable license metadata.
- Retry selected HTTP/transport failures and publish output atomically.
- Package as a Cabal library/executable/test suite, built through a pinned Nix flake.
- Add namespaced modules, Haddock documentation, Tasty regression tests and
  QuickCheck properties.

Full default live discovery remains unverified. See docs/testing.md.
