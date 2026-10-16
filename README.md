# Firefox add-on fetcher

A GPLv3 Haskell program that fetches Mozilla AMO metadata and writes a fresh
JSON Lines catalogue. Nix builds the executable; a separate Nix consumer can
turn the catalogue into extension packages. This program neither downloads
XPI archives nor configures Firefox.

## Usage

```sh
nix run . -- selected addons.jsonl ublock-origin keepassxc-browser
nix run . -- discover addons.jsonl
nix run . -- discover popular.jsonl 100000
```

`selected` fetches exactly the requested slugs (duplicates are fetched once).
`discover` searches Firefox extensions with at least one daily user by default;
the optional nonnegative integer changes that minimum. Themes, dictionaries and
language packs are excluded. Selected slugs accept ASCII letters, digits, `-`, `_`.

Output paths are relative to your current directory. Parent directories must
exist. Each successful run replaces the output with a **fresh catalogue**; no old
catalogue is read or merged. Errors and progress go to stderr. Failures return a
nonzero exit status and do not replace an existing output. Empty snapshots are
refused. Run only one writer per output file.

## Development

```sh
nix develop -c cabal build all --offline -fstrict
nix develop -c cabal test all --offline -fstrict --test-show-details=direct
nix develop -c cabal haddock all --offline
nix develop -c cabal check
nix develop -c cabal sdist
nix flake check
```

The `.cabal` file declares a reusable library, executable and Tasty test suite.
`flake.lock` pins the compiler/dependencies. No Bash launcher or custom test loop
is required. Tests use fixtures/local HTTP, not live Mozilla requests.

## Documentation

- [Architecture and responsibility boundary](docs/architecture.md)
- [JSONL schema and compatibility](docs/jsonl-schema.md)
- [Testing and verification limits](docs/testing.md)
- [Haskell conventions and references](docs/conventions.md)
- [Contribution workflow](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

Haddock API documentation is generated from `src/FirefoxAddons/*.hs` by Cabal
and by the Nix package build. The build prints the generated HTML location.

## Limits

Discovery partitions user-count ranges around AMO's current 30,000-result cap.
It tolerates changing counts, page lengths and overlapping GUIDs, keeping the last
observed record per GUID. Growing capped ranges are repartitioned; indivisible
capped buckets, invalid responses, HTTP failures and final slug collisions still
abort. The catalogue is best-effort, not a point-in-time snapshot: moving entries
may be missed and removed entries may remain. Full default live discovery has not
yet been verified. A bounded live three-page run previously produced 111 records.

Retries allow four attempts, with 1/2/4-second fallback waits and longer valid
`Retry-After` delays. No global deadline, response-size bound or resume state is
implemented. Atomic rename provides visibility, not power-loss durability or
writer locking; existing output permissions are not preserved.

## License

Project source: [GNU GPL version 3 only](LICENSE), SPDX `GPL-3.0-only`.
This does not relicense third-party extension metadata or the extensions whose
licenses are recorded in the output. Fixture provenance is documented in
[test/fixtures/README.md](test/fixtures/README.md).
