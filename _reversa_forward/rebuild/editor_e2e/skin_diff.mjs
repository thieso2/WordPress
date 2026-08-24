// Quantifies the skin match: probes the SAME computed properties on both systems and diffs.
// Content differs between the two, so a raw pixel diff would be meaningless — what is
// actually claimed by DEV-014 is that the visual SYSTEM matches, so that is what is measured.
import { chromium } from "playwright";
const b = await chromium.launch();
async function sess(base, isOracle) {
  const c = await b.newContext({ baseURL: base, viewport:{width:1280,height:900}, deviceScaleFactor:1 });
  const p = await c.newPage();
  if (isOracle) { await p.goto("/wp-login.php"); await p.fill('#user_login','oracle_admin'); await p.fill('#user_pass','oracle-admin-pw');
    await Promise.all([p.waitForLoadState('networkidle'), p.click('#wp-submit')]); await p.goto(base+"/wp-admin/edit.php",{waitUntil:'domcontentloaded'}); }
  else { await p.goto("/login"); await p.fill('input[name="log"]','oracle_admin'); await p.fill('input[name="pwd"]','oracle-admin-pw');
    await p.check('input[name="testcookie"]').catch(()=>{});
    await Promise.all([p.waitForLoadState('networkidle'), p.click('button[type=submit],input[type=submit]')]);
    await p.goto(base+"/console/posts",{waitUntil:'domcontentloaded'}); }
  await p.waitForTimeout(500);
  return p;
}
// [label, oracleSelector, rebuildSelector, props]
const PROBES = [
  ["body",            "body", "body", ["backgroundColor","color","fontFamily","fontSize"]],
  ["admin bar",       "#wpadminbar", ".adminbar", ["backgroundColor","height","fontSize"]],
  ["admin menu",      "#adminmenuwrap", ".adminmenu", ["backgroundColor","width"]],
  ["menu link",       "#adminmenu li.menu-top > a.menu-top", ".adminmenu > ul > li > a", ["color","fontSize","fontWeight"]],
  ["menu current",    "#adminmenu li.wp-has-current-submenu > a, #adminmenu li.current > a", ".adminmenu > ul > li.current > a", ["backgroundColor","color"]],
  ["submenu",         "#adminmenu .wp-submenu", ".adminmenu .sub", ["backgroundColor","fontSize"]],
  ["submenu link",    "#adminmenu .wp-submenu a", ".adminmenu .sub a", ["color","fontSize"]],
  ["h1",              ".wrap h1", ".wrap h1", ["fontSize","fontWeight","color"]],
  ["list table",      "table.wp-list-table", "table.wp-list-table", ["backgroundColor","fontSize","borderTopColor"]],
  ["table th",        "table.wp-list-table thead th", "table.wp-list-table thead th", ["color","fontSize","fontWeight","textAlign"]],
  ["table td",        "table.wp-list-table tbody td", "table.wp-list-table tbody td", ["fontSize","color"]],
  ["row title",       ".row-title", ".row-title", ["color","fontWeight","fontSize"]],
  ["row actions",     ".row-actions", ".row-actions", ["color","fontSize"]],
  ["primary button",  ".button-primary", ".button-primary", ["backgroundColor","color","borderRadius","fontSize"]],
  ["text input",      "input[type=search]", "input[type=search]", ["borderTopColor","borderRadius","fontSize","minHeight"]],
  ["select",          "select", "select", ["borderTopColor","borderRadius","fontSize","height"]],
  ["status tabs",     ".subsubsub", ".subsubsub", ["fontSize","color"]],
];
const grab = (page, sel, props) => page.evaluate(([sel,props]) => {
  const el = document.querySelector(sel); if (!el) return null;
  const cs = getComputedStyle(el); const o={}; for (const k of props) o[k]=cs[k]; return o;
}, [sel, props]);

const o = await sess("http://127.0.0.1:8099", true);
const r = await sess("http://127.0.0.1:3100", false);
let same=0, diff=0, missing=0; const deltas=[];
for (const [label, os, rs, props] of PROBES) {
  const a = await grab(o, os, props), c = await grab(r, rs, props);
  if (!a || !c) { missing++; console.log(`  ?  ${label.padEnd(16)} ${!a?'(not on oracle)':'(not on rebuild)'}`); continue; }
  for (const k of props) {
    if (a[k] === c[k]) same++;
    else { diff++; deltas.push(`  ✗  ${label.padEnd(16)} ${k.padEnd(16)} oracle=${a[k]}  rebuild=${c[k]}`); }
  }
}
deltas.forEach(d=>console.log(d));
const total = same+diff;
console.log(`\nMATCH: ${same}/${total} computed properties identical (${(same/total*100).toFixed(1)}%)  |  probes missing: ${missing}`);
await b.close();
