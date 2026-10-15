# JSON Lines schema

Output is UTF-8. Each nonempty line contains one compact JSON object. There is a
final newline, no enclosing array, and records are sorted by slug. JSON object
key order is not an interface guarantee. Embedded string newlines are escaped.
An empty completed catalogue is rejected.

## Fields

- `guid` — nonempty extension identity from AMO; used for deduplication.
- `slug` — nonempty AMO slug; intended as the external package attribute name.
- `version` — nonempty current-version string.
- `url` — HTTPS XPI download URL reported by AMO.
- `hash` — exactly 64 hexadecimal SHA-256 digits; AMO's `sha256:` prefix is removed.
- `permissions` — string array from AMO; an explicitly empty array is supported.
  A missing permissions field is not silently treated as no permissions.
- `license` — AMO license slug or JSON `null` for missing/custom/unknown slugs.

Unknown licensing does not establish permission to redistribute. The Nix consumer
must choose a conservative mapping rather than assuming a free license.

The hash format is validated, not the XPI bytes: byte verification belongs to the
Nix fixed-output fetch. This tool does not fetch the archives. AMO response
schemas and this output schema differ deliberately; `FromJSON Addon` reads AMO,
while `ToJSON Addon` emits normalized metadata. They are not a round-trip codec.

## Nix consumer boundary

Read lines and discard empty split elements caused by the final newline before
calling `builtins.fromJSON`. Map license slugs separately and package each signed
XPI without repacking it. This project contains no extension-packaging overlay.

## Compatibility

This is the initial 0.1 schema, not a promised stable API. Changing field names,
meaning, or nullability requires updating consumer code, fixtures, tests and the
changelog. No generated catalogue is included in the package source.
