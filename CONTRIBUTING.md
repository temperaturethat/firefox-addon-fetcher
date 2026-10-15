# Contributing

Use the pinned Nix development environment. Keep the Haskell program limited to
AMO metadata acquisition and JSONL generation; extension derivations and browser
profile installation belong to Nix/Home Manager, not this executable.

## Checks

```sh
nix develop -c cabal check
nix develop -c cabal build all --offline -fstrict
nix develop -c cabal test all --offline -fstrict --test-show-details=direct
nix develop -c cabal haddock all --offline
nix develop -c cabal sdist
nix flake check
```

`-fstrict` enables `-Werror` for development/CI, not for downstream builds by
default. Dependency bounds declare the supported compiler family; extend them
only with a tested compiler/dependency set. Cabal uses no Hackage repositories
in this project: Nix supplies dependencies, including test dependencies.

## Code and tests

- Namespace library modules under `FirefoxAddons`; match module names to paths.
- Keep `app/Main.hs` as CLI orchestration, not the home of reusable logic.
- Use explicit exports, top-level signatures and Haddock `-- |` comments on APIs.
- Keep pure transforms separate from HTTP/filesystem effects. Inject effects in tests.
- Use Tasty/HUnit assertions rather than calling `exitFailure` inside test helpers.
- Add a failing regression test before changing behavior; retain offline tests.
- Use properties for invariants, unit cases for boundaries, and loopback HTTP for integration.
- Use temporary directories under the environment's temporary directory; clean up resources.
- Keep fixtures in `test/fixtures`, declared as Cabal data files and accessed via
  `Paths_firefox_addon_fetcher.getDataFileName` so source distributions work too.

## Formatting

Fourmolu formats Haskell; nixfmt formats Nix. Both are supplied by `nix develop`.
For example:

```sh
nix develop -c fourmolu -i src/FirefoxAddons/Model.hs app/Main.hs
nix fmt
```

The project uses two-space indentation, UTF-8 and final newlines via EditorConfig.
No remote publication/CI provider is assumed. Work on a task branch and review
changes before committing. Do not commit generated catalogues, build directories,
credentials, or ad-hoc store executable paths.
