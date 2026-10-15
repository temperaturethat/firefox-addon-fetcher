# Architecture

## Boundary

```text
AMO API -> Haskell fetcher -> JSONL snapshot -> external Nix consumer
```

The fetcher does not install extensions or generate Nix expressions. Nix builds
this Cabal package, and a different Nix consumer fetches/verifies pinned XPIs.
Live AMO requests occur only when explicitly executing the fetcher, never in
pure Nix evaluation or its package build.

## Components

- `FirefoxAddons.Model`: AMO decoding, schema normalization and canonicalization.
- `FirefoxAddons.Http`: one JSON GET, with transport/status/decode error values.
- `FirefoxAddons.Retry`: error classification and an injected-clock retry loop.
- `FirefoxAddons.Discover`: user-count partitioning and page consistency checks.
- `FirefoxAddons.Generate`: selected requests, fresh snapshots and error boundaries.
- `FirefoxAddons.JsonLines`: pure UTF-8 JSONL encoding.
- `FirefoxAddons.Publish`: same-directory temporary file and final rename.
- `app/Main.hs`: CLI arguments, request pacing and diagnostics.

The library is shared by the executable and tests through Cabal dependencies,
not compiled afresh by manually listing every source file.

## Discovery

Request Firefox extensions sorted by users descending, then creation time.
If a search count exceeds the 30,000 window, bisect its inclusive integer daily-user
range. For an open upper bound use the maximum count in the users-descending first
page. The ranges are disjoint. Once a range fits, fetch its pages sequentially.

Check page counts, lengths, range membership and repeated GUIDs. Compare the
combined child count with the parent count. Any observed drift aborts. If one
exact user-count bucket exceeds the cap, abort: creation-date subdivision is not
implemented. A zero-result AMO response can report one page; empty internal
partitions are allowed, but an empty final snapshot is refused.

These checks are conservative failure guards, not a globally consistent snapshot
protocol. Metadata or counts can change during a crawl without every change being
detectable. An unsplittable bucket or schema change requires code changes, not
silent omission of records.

## Errors and publication

`FetchError` distinguishes HTTP statuses, transport exceptions and JSON errors.
Only selected transient classes retry, with four total action attempts and no
sleep after the final failure. HTTP dates and numeric `Retry-After` are understood;
longer server-directed waits win over fallback backoff. Cancellation propagates.

The fetcher canonicalizes the entire result before writing any output. Identical
GUID duplicates collapse; conflicting GUID data or cross-GUID slug collisions abort.
It never reads or reconciles the previous output. Writing uses a temporary file
beside the destination followed by rename. On Linux, readers opening the file see
the old or new contents, not a partial update. This is not fsync durability, a
concurrent-writer lock, or permission-preserving replacement.
