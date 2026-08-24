import { chromium } from "playwright";
const b = await chromium.launch();
async function go(base, isOracle, url) {
  const c = await b.newContext({ baseURL: base, viewport:{width:1280,height:900} });
  const p = await c.newPage();
  if (isOracle) { await p.goto("/wp-login.php"); await p.fill('#user_login','oracle_admin'); await p.fill('#user_pass','oracle-admin-pw');
    await Promise.all([p.waitForLoadState('networkidle'), p.click('#wp-submit')]); }
  else { await p.goto("/login"); await p.fill('input[name="log"]','oracle_admin'); await p.fill('input[name="pwd"]','oracle-admin-pw');
    await p.check('input[name="testcookie"]').catch(()=>{});
    await Promise.all([p.waitForLoadState('networkidle'), p.click('button[type=submit],input[type=submit]')]); }
  await p.goto(base+url,{waitUntil:'domcontentloaded'}); await p.waitForTimeout(500);
  return p;
}
const o = await go("http://127.0.0.1:8099", true, "/wp-admin/edit.php");
const r = await go("http://127.0.0.1:3100", false, "/console/posts");
// A NON-current submenu link on each side
const nc = (p, sel) => p.evaluate((s)=>{ const els=[...document.querySelectorAll(s)];
  const el = els.find(e=>!e.closest('li')?.classList.contains('current') && e.getAttribute('aria-current')!=='page');
  return el ? getComputedStyle(el).color : null; }, sel);
console.log("non-current submenu link  oracle:", await nc(o,'#adminmenu .wp-submenu a'), " rebuild:", await nc(r,'.adminmenu .sub a'));
// the CURRENT submenu link
const cur = (p, sel) => p.evaluate((s)=>{ const e=document.querySelector(s); return e?getComputedStyle(e).color:null; }, sel);
console.log("current submenu link      oracle:", await cur(o,'#adminmenu .wp-submenu li.current a'), " rebuild:", await cur(r,'.adminmenu .sub a[aria-current=page]'));
// which element is .button-primary on the oracle posts screen?
console.log("oracle .button-primary is:", await o.evaluate(()=>{const e=document.querySelector('.button-primary'); return e? (e.tagName+'#'+(e.id||'')+'.'+e.className+' value='+(e.value||e.textContent||'').trim().slice(0,20)) : null;}));
console.log("rebuild search submit cls:", await r.evaluate(()=>{const e=document.querySelector('.search-box button, .search-box input[type=submit]'); return e? (e.tagName+'.'+e.className) : null;}));
await b.close();
