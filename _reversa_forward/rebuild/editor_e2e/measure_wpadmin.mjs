// Measures wp-admin's ACTUAL computed styles from the live oracle, so the rebuild's skin is
// matched against observed values rather than guessed from SCSS sources.
import { chromium } from "playwright";
const b = await chromium.launch();
const c = await b.newContext({ baseURL: "http://127.0.0.1:8099", viewport: { width: 1280, height: 900 } });
const p = await c.newPage();
await p.goto("/wp-login.php");
await p.fill('#user_login', 'oracle_admin'); await p.fill('#user_pass', 'oracle-admin-pw');
await Promise.all([p.waitForLoadState('networkidle'), p.click('#wp-submit')]);
await p.goto("/wp-admin/edit.php", { waitUntil: 'domcontentloaded' });

const probe = async (sel, props) => {
  return await p.evaluate(([sel, props]) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const cs = getComputedStyle(el);
    const o = {}; for (const k of props) o[k] = cs[k];
    return o;
  }, [sel, props]);
};
const BOX = ['backgroundColor','color','fontFamily','fontSize','fontWeight','lineHeight','padding','margin','border','borderRadius'];
const out = {};
out.body        = await probe('body', ['backgroundColor','color','fontFamily','fontSize','lineHeight']);
out.adminbar    = await probe('#wpadminbar', ['backgroundColor','color','height','fontSize','fontFamily']);
out.adminbarLink= await probe('#wpadminbar .ab-item', ['color','fontSize','padding','lineHeight']);
out.adminmenu   = await probe('#adminmenuwrap', ['backgroundColor','width']);
out.menuTop     = await probe('#adminmenu li.menu-top > a', ['backgroundColor','color','fontSize','fontWeight','padding','lineHeight']);
out.menuCurrent = await probe('#adminmenu li.current > a, #adminmenu li.wp-has-current-submenu > a', ['backgroundColor','color','fontWeight','boxShadow']);
out.submenu     = await probe('#adminmenu .wp-submenu', ['backgroundColor','padding','fontSize']);
out.submenuLink = await probe('#adminmenu .wp-submenu a', ['color','fontSize','padding','lineHeight']);
out.wpcontent   = await probe('#wpcontent', ['padding','marginLeft']);
out.h1          = await probe('.wrap h1', ['fontSize','fontWeight','color','margin','padding','lineHeight','fontFamily']);
out.table       = await probe('table.wp-list-table', ['backgroundColor','border','borderRadius','boxShadow','fontSize']);
out.th          = await probe('table.wp-list-table thead th', ['backgroundColor','color','fontSize','fontWeight','padding','borderBottom','textAlign']);
out.td          = await probe('table.wp-list-table tbody td', ['padding','fontSize','color','borderBottom','lineHeight']);
out.rowTitle    = await probe('table.wp-list-table .row-title', ['color','fontWeight','fontSize','textDecoration']);
out.rowActions  = await probe('.row-actions', ['color','fontSize','padding','visibility']);
out.button      = await probe('.button', ['backgroundColor','color','border','borderRadius','fontSize','padding','lineHeight','boxShadow','height']);
out.buttonPri   = await probe('.button-primary', ['backgroundColor','color','border','borderRadius','textShadow','boxShadow']);
out.input       = await probe('input[type=search], input[type=text]', ['border','borderRadius','padding','fontSize','backgroundColor','color','boxShadow','minHeight']);
out.select      = await probe('select', ['border','borderRadius','padding','fontSize','height','backgroundColor']);
out.subsubsub   = await probe('.subsubsub', ['fontSize','margin','color','padding']);
out.tablenav    = await probe('.tablenav', ['height','margin','padding','backgroundColor']);
out.notice      = await probe('.notice, .updated', ['backgroundColor','border','borderLeft','padding','margin','boxShadow']);
out.formTableTh = await probe('.form-table th', ['width','padding','fontSize','fontWeight','textAlign','color','lineHeight']);
console.log(JSON.stringify(out, null, 1));
await b.close();
