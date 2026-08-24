# Visual verification report

`oracle-vs-rebuild.html` — a self-contained page pairing every screen in the parity corpus,
plus the admin/console surface, as rendered by the WordPress 7.2-alpha-63330 oracle and by
the Rails rebuild.

Regenerate:

```bash
bin/oracle up                          # WordPress on :8099
bin/rails server -p 3100               # the rebuild on :3100
cd /tmp/shots
node shoot.mjs                         # the 25 front-end corpus screens
node shoot_admin.mjs                   # the 28 console screens (signs in on both sides)
node build2.mjs                        # emits oracle-vs-rebuild.html
```

`shoot.mjs` reads `spec/parity/corpus/requests.yml` — the same file the parity harness
reads — so the report and the harness cannot describe different sets of screens.

`shoot_admin.mjs` signs in as the seeded administrator (`oracle_admin`) on BOTH systems; the
rebuild accepts the oracle's migrated password digest (T-10), so one credential opens both.
Its screen list is explicit rather than derived: the console is modernized, so there is no
corpus file to read from.

`build2.mjs` reads `_report.css` for the shared design tokens. Screenshots are captured as
JPEG directly by Playwright (no ImageMagick in this environment) and inlined as data URIs,
which is what keeps the page self-contained and under the artifact size cap.

XML surfaces are fetched and rendered as source rather than navigated to: Chromium treats
`application/xml` as a download and hangs waiting for a save dialog.

## Two contracts, deliberately not blurred

The 25 front-end screens are **literal** — byte-comparable through the parity harness. The
console is **modernized** (`screen_modernization_decision.md`): literal strings verbatim,
data and behaviour matching, structure free. There are no golden files for the console, so
the report shows those pairs for inspection and says so, rather than implying pixel parity.
