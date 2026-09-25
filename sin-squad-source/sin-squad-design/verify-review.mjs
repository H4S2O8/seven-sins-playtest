import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {chromium} from 'file:///C:/Users/27654/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';

const root=import.meta.dirname;
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
const errors=[];
try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}});
 page.on('pageerror',e=>errors.push(String(e)));
 await page.goto(pathToFileURL(path.join(root,'review.html')).href);
 assert.equal(await page.locator('nav button').count(),8);
 await page.locator('[data-tab="1"]').click();
 assert.equal(await page.locator('#doc1 h3').count(),98);
 await page.locator('[data-tab="2"]').click();
 assert.equal(await page.locator('#doc2 h3').count(),100);
 await page.locator('[data-tab="search"]').click();
 await page.locator('#query').fill('EQ43');
 assert.ok(await page.locator('[data-id="EQ43"]').count());
 await page.locator('[data-id="EQ43"]').click();
 assert.equal(await page.locator('#EQ43').isVisible(),true);
 await page.screenshot({path:path.join(root,'review-desktop.png')});
 await page.setViewportSize({width:390,height:844});
 await page.locator('[data-tab="5"]').click();
 assert.equal(await page.locator('#doc5').isVisible(),true);
 const width=await page.evaluate(()=>({scroll:document.documentElement.scrollWidth,view:innerWidth}));
 assert.ok(width.scroll<=width.view+1,JSON.stringify(width));
 await page.screenshot({path:path.join(root,'review-mobile.png')});
 assert.deepEqual(errors,[]);
 const result={passed:true,checks:['六个章节与全文可切换','人物98条可读','装备与效果100条可读','编号搜索与跳转正常','390px窄屏无横向溢出','无页面脚本错误'],scope:'仅设计稿阅读页；不是游戏战斗验证'};
 fs.writeFileSync(path.join(root,'review-check.json'),JSON.stringify(result,null,2));
 console.log(JSON.stringify(result,null,2));
}finally{await browser.close();}
