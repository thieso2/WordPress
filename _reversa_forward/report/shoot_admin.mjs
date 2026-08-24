// Captures the ADMIN/CMS surface on both sides: wp-admin (oracle) beside the rebuild's
// console. Both sides are signed in as the same seeded administrator — the rebuild
// migrated the oracle's password digest (T-10), so one credential opens both.
//
// Unlike the front-end corpus (which the parity harness compares byte-for-byte), the
// console is MODERNIZED: screen_modernization_decision.md makes it a semantic contract —
// literal strings verbatim, data and behaviour matching, structure free. So these pairs
// are shown for inspection, never graded on pixel identity.
import { chromium } from 'playwright';
import { writeFileSync, mkdirSync } from 'node:fs';

const ORACLE = 'http://127.0.0.1:8099';
const REBUILD = 'http://127.0.0.1:3100';
const OUT = '/tmp/shots/out';
mkdirSync(OUT, { recursive: true });

const USER = 'oracle_admin';
const PASS = 'oracle-admin-pw';

// screen id, oracle path, rebuild path, group, note
const SCREENS = [
  ['console.index',            '/wp-admin/index.php',                              '/console',                        'core',    'Dashboard — At a Glance, Activity, Quick Draft'],
  ['console.edit',             '/wp-admin/edit.php',                               '/console/posts',                  'core',    'Posts list (P-LIST): filters, row + bulk actions'],
  ['console.edit-pages',       '/wp-admin/edit.php?post_type=page',                '/console/pages',                  'core',    'Pages list — hierarchical ordering'],
  ['console.upload',           '/wp-admin/upload.php',                             '/console/media',                  'core',    'Media library'],
  ['console.media-new',        '/wp-admin/media-new.php',                          '/console/media/new',              'core',    'Upload Media'],
  ['console.edit-comments',    '/wp-admin/edit-comments.php',                      '/console/comments',               'core',    'Comments + moderation'],
  ['console.edit-tags-cat',    '/wp-admin/edit-tags.php?taxonomy=category',        '/console/terms/category',         'core',    'Categories — Add form + Quick Edit'],
  ['console.edit-tags-tag',    '/wp-admin/edit-tags.php?taxonomy=post_tag',        '/console/terms/post_tag',         'core',    'Tags'],
  ['console.users',            '/wp-admin/users.php',                              '/console/users',                  'core',    'Users list'],
  ['console.user-new',         '/wp-admin/user-new.php',                           '/console/users/new',              'core',    'Add User'],
  ['console.profile',          '/wp-admin/profile.php',                            '/console/profile',                'core',    'Profile'],

  ['console.options-general',  '/wp-admin/options-general.php',                    '/console/settings/general',       'settings','General settings'],
  ['console.options-writing',  '/wp-admin/options-writing.php',                    '/console/settings/writing',       'settings','Writing settings'],
  ['console.options-reading',  '/wp-admin/options-reading.php',                    '/console/settings/reading',       'settings','Reading settings'],
  ['console.options-discussion','/wp-admin/options-discussion.php',                '/console/settings/discussion',    'settings','Discussion settings'],
  ['console.options-media',    '/wp-admin/options-media.php',                      '/console/settings/media',         'settings','Media settings'],
  ['console.options-permalink','/wp-admin/options-permalink.php',                  '/console/settings/permalinks',    'settings','Permalinks'],

  ['console.tools',            '/wp-admin/tools.php',                              '/console/tools',                  'tools',   'Tools'],
  ['console.export',           '/wp-admin/export.php',                             '/console/tools/export',           'tools',   'Export'],
  ['console.export-personal',  '/wp-admin/export-personal-data.php',               '/console/tools/export-personal-data','tools','Export personal data (GDPR)'],
  ['console.erase-personal',   '/wp-admin/erase-personal-data.php',                '/console/tools/erase-personal-data','tools', 'Erase personal data (GDPR)'],
  ['console.site-health',      '/wp-admin/site-health.php',                        '/console/tools/site-health',      'tools',   'Site Health'],
  ['console.site-health-info', '/wp-admin/site-health.php?tab=debug',              '/console/tools/site-health/info', 'tools',   'Site Health — Info'],

  ['console.themes',           '/wp-admin/themes.php',                             '/console/themes',                 'appearance','Themes'],
  ['console.theme-install',    '/wp-admin/theme-install.php',                      '/console/themes/new',             'appearance','Add Themes'],
  ['console.nav-menus',        '/wp-admin/nav-menus.php',                          '/console/menus',                  'appearance','Menus'],
];

// The two editor screens need a record id, which differs per side; resolved at runtime.
const esc = (t) => String(t).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);

const browser = await chromium.launch();

async function signedInContext(side) {
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1,
    colorScheme: 'light', reducedMotion: 'reduce',
  });
  const page = await ctx.newPage();
  if (side === 'oracle') {
    await page.goto(`${ORACLE}/wp-login.php`, { waitUntil: 'domcontentloaded' });
    await page.fill('#user_login', USER);
    await page.fill('#user_pass', PASS);
    await Promise.all([page.waitForLoadState('networkidle'), page.click('#wp-submit')]);
  } else {
    await page.goto(`${REBUILD}/login`, { waitUntil: 'domcontentloaded' });
    await page.fill('input[name="log"]', USER);
    await page.fill('input[name="pwd"]', PASS);
    await page.check('input[name="testcookie"]').catch(() => {});
    await Promise.all([page.waitForLoadState('networkidle'), page.click('button[type=submit],input[type=submit]')]);
  }
  return { ctx, page };
}

const oracleSess = await signedInContext('oracle');
const rebuildSess = await signedInContext('rebuild');

// Resolve an editable post id on each side so the editor screens land on a real record.
async function firstPostId(page, side) {
  if (side === 'oracle') {
    await page.goto(`${ORACLE}/wp-admin/edit.php`, { waitUntil: 'domcontentloaded' });
    const href = await page.locator('a.row-title').first().getAttribute('href').catch(() => null);
    const m = href && href.match(/post=(\d+)/); return m ? m[1] : null;
  }
  await page.goto(`${REBUILD}/console/posts`, { waitUntil: 'domcontentloaded' });
  const href = await page.locator('a[href*="/console/posts/"][href$="/edit"]').first().getAttribute('href').catch(() => null);
  const m = href && href.match(/posts\/(\d+)\/edit/); return m ? m[1] : null;
}
const oId = await firstPostId(oracleSess.page, 'oracle');
const rId = await firstPostId(rebuildSess.page, 'rebuild');
if (oId && rId) {
  SCREENS.push(['console.post', `/wp-admin/post.php?post=${oId}&action=edit`, `/console/posts/${rId}/edit`, 'editor',
                'The block editor — Gutenberg (oracle) vs the React island (rebuild)']);
}
SCREENS.push(['console.site-editor', '/wp-admin/site-editor.php', '/console/site-editor', 'editor',
              'The Site Editor — templates, parts and Global Styles']);

const results = [];
for (const [screen, opath, rpath, group, note] of SCREENS) {
  const row = { screen, group, note, paths: { oracle: opath, rebuild: rpath }, shots: {} };
  for (const [side, base, sess] of [['oracle', ORACLE, oracleSess], ['rebuild', REBUILD, rebuildSess]]) {
    const page = sess.page;
    const path = side === 'oracle' ? opath : rpath;
    const file = `${screen.replace(/\./g, '-')}--${side}.jpg`;
    try {
      const resp = await page.goto(base + path, { waitUntil: 'domcontentloaded', timeout: 20000 });
      const status = resp ? resp.status() : 0;
      // Editor screens mount a JS app; give them a moment to render.
      await page.waitForTimeout(screen.includes('editor') || screen === 'console.post' ? 3500 : 700);
      await page.addStyleTag({ content: '*,*::before,*::after{animation:none!important;transition:none!important;caret-color:transparent!important}' });
      await page.screenshot({ path: `${OUT}/${file}`, fullPage: false, type: 'jpeg', quality: 62 });
      row.shots[side] = { file, status, title: await page.title() };
    } catch (err) {
      row.shots[side] = { file: null, status: 0, error: String(err).split('\n')[0] };
    }
  }
  const o = row.shots.oracle?.status, r = row.shots.rebuild?.status;
  row.statusMatch = o === r;
  console.log(`${row.statusMatch ? '  ' : '!!'} ${screen.padEnd(28)} oracle=${o} rebuild=${r}`);
  results.push(row);
}

await browser.close();
writeFileSync(`${OUT}/admin_results.json`, JSON.stringify(results, null, 2));
console.log(`\n${results.length} admin screens captured, ${results.filter((r) => r.statusMatch).length} status-matched`);
