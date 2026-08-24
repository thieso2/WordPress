import { chromium } from "playwright";
const b = await chromium.launch(); const c = await b.newContext({ baseURL:"http://127.0.0.1:8099", viewport:{width:1280,height:900}});
const p = await c.newPage();
await p.goto("/wp-login.php"); await p.fill('#user_login','oracle_admin'); await p.fill('#user_pass','oracle-admin-pw');
await Promise.all([p.waitForLoadState('networkidle'), p.click('#wp-submit')]);
await p.goto("/wp-admin/edit.php",{waitUntil:'domcontentloaded'});
const m = await p.evaluate(() => {
  const g=(s,ps)=>{const e=document.querySelector(s); if(!e) return null; const cs=getComputedStyle(e); const o={}; for(const k of ps)o[k]=cs[k]; o._h=e.getBoundingClientRect().height; return o;};
  return {
    topLink: g('#adminmenu li.menu-top > a.menu-top',['padding','fontSize','lineHeight','minHeight']),
    icon: g('#adminmenu .wp-menu-image',['width','height','fontSize','padding','float']),
    subLi: g('#adminmenu .wp-submenu li',['padding','margin','fontSize']),
    rowActions: g('.row-actions',['visibility','position','left']),
    commentBubble: g('.post-com-count .comment-count',['backgroundColor','color','borderRadius','fontSize','padding','minWidth','lineHeight']),
  };
});
console.log(JSON.stringify(m,null,1)); await b.close();
