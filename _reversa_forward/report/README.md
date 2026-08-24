# Visual verification report

`oracle-vs-rebuild.html` — a self-contained page pairing every screen in the parity corpus
as rendered by the WordPress 7.2-alpha-63330 oracle and by the Rails rebuild.

Regenerate:

```bash
bin/oracle up                                   # WordPress on :8099
bin/rails server -p 3100                        # the rebuild on :3100
cd /tmp/shots && node shoot.mjs && node build.mjs
```

`shoot.mjs` reads `spec/parity/corpus/requests.yml` — the same file the parity harness
reads — so the report and the harness cannot describe different sets of screens.

XML surfaces are fetched and rendered as source rather than navigated to: Chromium treats
`application/xml` as a download and hangs waiting for a save dialog.
