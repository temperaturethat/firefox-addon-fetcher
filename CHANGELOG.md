# Changelog

## 0.1.0.0 — Unreleased

- Generate fresh JSONL for selected extensions or paginated AMO discovery.
- Partition oversized searches by daily-user range; abort rather than truncate.
- Include permissions and nullable license metadata.
- Retry selected HTTP/transport failures and publish output atomically.
- Package as a Cabal library/executable/test suite, built through a pinned Nix flake.
- Add namespaced modules, Haddock documentation, Tasty regression tests and
  QuickCheck properties.

Full default live discovery remains unverified. See docs/testing.md.
