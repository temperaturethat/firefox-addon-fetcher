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
- `FirefoxAddons.Discover`: live pagination, user-count partitioning and observation deduplication.
- `FirefoxAddons.Generate`: selected requests, fresh snapshots and error boundaries.
- `FirefoxAddons.JsonLines`: pure UTF-8 JSONL encoding.
- `FirefoxAddons.Publish`: same-directory temporary file and final rename.
- `app/Main.hs`: CLI arguments, request pacing and diagnostics.

The library is shared by the executable and tests through Cabal dependencies,
not compiled afresh by manually listing every source file.

## Discovery

Request Firefox extensions sorted by users descending, then creation time.
Counts and page counts are advisory and can change during the crawl. Follow each
response's current page count, rather than freezing the first page's total. Short
or empty pages do not contradict an earlier count; continue if the current page
hint advertises more pages. A decreasing page hint stops stale follow-up requests.

Every response is checked against the 30,000-result search window. If the count
or advertised pages exceed it, bisect the user-count range and query its children.
The maximum user count observed so far supplies a split point for an open range,
not a permanent ceiling: the right child keeps its open upper bound. Observations
already collected before a split are retained, followed by child observations.
Parent and child totals need not agree. If one exact user-count bucket exceeds
the cap, abort; creation-date subdivision is not implemented.

Repeated GUIDs caused by page overlap or movement across partitions are normal.
Keep the last observed complete record per GUID, then sort by slug and reject
remaining cross-GUID slug collisions. Last observed does not mean newest version:
a cached later response can be older. Selected mode retains strict conflict checks.
Malformed metadata, oversized pages, out-of-range results, and HTTP failures still
abort. Empty internal ranges are allowed; an empty final catalogue is refused.

The output is a best-effort catalogue of records observed over time, not an exact
point-in-time snapshot. Offset pagination can miss entries as ordering changes;
entries removed after observation can remain. Neither count equality nor GUID
deduplication can prove completeness. A page removed between requests may return
an HTTP error, which still aborts under the HTTP failure policy. There is no
resume state, global deadline or snapshot API. Do not present the output count as
an exact count of all current extensions.

## Errors and publication

`FetchError` distinguishes HTTP statuses, transport exceptions and JSON errors.
Only selected transient classes retry, with four total action attempts and no
sleep after the final failure. HTTP dates and numeric `Retry-After` are understood;
longer server-directed waits win over fallback backoff. Cancellation propagates.

The fetcher canonicalizes the entire result before writing any output. Discovery
resolves repeated GUIDs by observation order; selected mode rejects conflicting
GUID data. Both reject cross-GUID final slug collisions.
It never reads or reconciles the previous output. Writing uses a temporary file
beside the destination followed by rename. On Linux, readers opening the file see
the old or new contents, not a partial update. This is not fsync durability, a
concurrent-writer lock, or permission-preserving replacement.
