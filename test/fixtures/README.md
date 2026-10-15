# Fixture provenance

`amo-page.json` is a saved real response from Mozilla AMO, fetched during development
from:

https://addons.mozilla.org/api/v5/addons/search/?app=firefox&type=extension&users__gte=1&page_size=50&sort=users,created&lang=en-US

It contains 50 public extension records, including custom-license metadata with a
null license slug. It is used offline for AMO schema regression tests, not as a
current production catalogue. API metadata/extension licensing is distinct from
the project's GPLv3 source license. No XPI files or extension source are included.

Do not refresh this fixture during a test. A deliberate refresh needs review of
schema changes and updated expectations. Synthetic HTTP error bodies and numeric
partition fixtures are declared in their corresponding test modules.
