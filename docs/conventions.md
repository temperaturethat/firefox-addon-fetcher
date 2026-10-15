# Haskell conventions used here

Haskell has no single mandatory repository layout. This project uses Cabal's
component model and established tools rather than a bespoke build script.

## Package structure

```text
firefox-addon-fetcher.cabal   package metadata, components and dependency bounds
cabal.project                  local project configuration
src/FirefoxAddons/             reusable namespaced library modules
app/Main.hs                    executable entry point
test/Main.hs                   Tasty runner
test/FirefoxAddons/*Spec.hs     unit/regression/integration groups
test/FirefoxAddons/Properties.hs QuickCheck invariants
test/fixtures/                 versioned API data with provenance
docs/                          design, schema, conventions and verification notes
```

The library, executable and `exitcode-stdio-1.0` test suite have separate Cabal
components. Each declares its direct dependencies; the executable/tests depend on
the library rather than relying on transitive package visibility. No custom
Setup.hs or Stack configuration is needed for `build-type: Simple`.

Use an explicit Haskell2010 baseline with local LANGUAGE pragmas where needed.
Use explicit module exports, top-level type signatures, two-space indentation,
qualified imports for competing APIs, and total pattern matches. `-Wall` and
selected completeness/compatibility warnings apply to all components. The manual
`strict` flag enables `-Werror` only when intentionally requested. Fourmolu provides
consistent formatting; stylistic choices are project conventions, not language laws.

## Documentation and tests

Haddock comments before modules/declarations describe invariants, required inputs,
effects and failure boundaries. README covers usage; CONTRIBUTING covers checks;
CHANGELOG records changes; detailed design/schema information lives in docs/.

Tasty combines HUnit examples, existing regression scenarios, QuickCheck properties
and local HTTP integration. Tests must throw assertion failures rather than exit
the entire runner. Saved fixtures use Cabal Paths lookup, not assumed working
directories. Tests do not query live AMO. Live smoke tests remain explicit and
are not evidence that all discovery partitions have been tested against production.

## References inspected

- [Cabal package description](https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html)
- [Haddock documentation markup](https://haskell-haddock.readthedocs.io/latest/markup.html)
- [Tasty components and providers](https://github.com/UnkindPartition/tasty)
- [Fourmolu](https://fourmolu.github.io/)
- [Package versioning policy](https://pvp.haskell.org/)

License selection is a project decision, not dictated by Haskell conventions:
the requested license here is GPL-3.0-only.
