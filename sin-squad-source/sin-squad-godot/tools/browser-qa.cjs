// Local isolated browser integration test. Never attaches to a user's browser/profile.
const path = require('node:path');
const fs = require('node:fs');
const { chromium } = require('C:/Users/27654/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const base = process.argv[2] || 'http://127.0.0.1:8943/';
if (!/^http:\/\/127\.0\.0\.1:\d+\/$/.test(base)) throw new Error('Only an explicitly local QA server is accepted');
const evidence = path.resolve(__dirname, '../evidence');
const browserPath = process.env.SIN_SQUAD_QA_BROWSER || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const clicks = process.argv.slice(3).filter(x => /^--click=\d+,\d+$/.test(x)).map(x => x.slice(8).split(',').map(Number));
(async () => {
  console.log('QA launching isolated browser');
  const browser = await chromium.launch({executablePath:browserPath,headless:true,timeout:25000,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  try {
    const page = await browser.newPage({viewport:{width:1280,height:720}, deviceScaleFactor:1});
    // Observe bytes the unmodified Godot preloader actually consumes. Some
    // Chromium stream requests report ERR_ABORTED after the full body was read;
    // never suppress that error merely because a screenshot happens to exist.
    await page.addInitScript(() => {
      window.__qaConsumedBodies = [];
      const originalFetch = window.fetch;
      window.fetch = async function (...args) {
        const response = await originalFetch.apply(this, args);
        if (!response.body || !/\/index\.(pck|wasm)$/.test(response.url)) return response;
        const record = {url:response.url,status:response.status,bytes:0,done:false,error:null};
        window.__qaConsumedBodies.push(record);
        const originalGetReader = response.body.getReader;
        response.body.getReader = function (...readerArgs) {
          const reader = originalGetReader.apply(this, readerArgs);
          const originalRead = reader.read;
          reader.read = async function (...readArgs) {
            try {
              const value = await originalRead.apply(this, readArgs);
              record.bytes += value.value?.byteLength || 0;
              if (value.done) {record.done = true;record.completedAt = Date.now();}
              return value;
            } catch (error) {record.error = String(error);throw error;}
          };
          return reader;
        };
        return response;
      };
    });
    page.setDefaultTimeout(20000);
    const messages=[], failures=[], completedRequests=[], abortedRequests=[], httpErrors=[];
    const savePartial=()=>fs.writeFileSync(path.join(evidence,'W05-browser-qa-partial.json'),JSON.stringify({url:base,browserPath,complete:false,messages,failures,completedRequests,abortedRequests,httpErrors},null,2));
    page.on('console', m => {messages.push({kind:m.type(),text:m.text()});savePartial();});
    page.on('pageerror', e => {failures.push(String(e));savePartial();});
    page.on('requestfailed', r => {abortedRequests.push({url:r.url(),error:r.failure()?.errorText,time:Date.now()});savePartial();});
    page.on('requestfinished', async r => {const response=await r.response();completedRequests.push({url:r.url(),status:response?.status(),time:Date.now()});savePartial();});
    page.on('response', r => {if(r.status()>=400){httpErrors.push({url:r.url(),status:r.status()});savePartial();}});
    console.log('QA navigating '+base);
    await page.goto(base,{waitUntil:'networkidle',timeout:45000});
    await page.waitForTimeout(2000);
    console.log('QA capturing viewport');
    await page.screenshot({path:path.join(evidence,'W05-browser-1280x720.png'),timeout:20000});
    for (let i=0;i<clicks.length;i++) {
      await page.mouse.click(clicks[i][0],clicks[i][1]);
      await page.waitForTimeout(700);
      await page.screenshot({path:path.join(evidence,`W05-browser-click-${i+1}.png`)});
    }
    const dom=await page.locator('body').innerText();
    const consumedBodies=await page.evaluate(()=>window.__qaConsumedBodies||[]);
    const completeBodyUrls=new Set();
    for (const body of consumedBodies) {
      const localFile=path.resolve(__dirname,'../web-preview',new URL(body.url).pathname.slice(1));
      const expectedBytes=fs.existsSync(localFile)?fs.statSync(localFile).size:null;
      body.expectedBytes=expectedBytes;
      body.exactBodyVerified=body.status===200 && body.done && !body.error && expectedBytes===body.bytes;
      if (body.exactBodyVerified) completeBodyUrls.add(body.url);
    }
    const recoveredRequests=[];
    for(const failure of abortedRequests){
      if(completedRequests.some(r=>r.url===failure.url&&r.status>=200&&r.status<300&&r.time>=failure.time)) recoveredRequests.push(failure);
      else if(failure.error==='net::ERR_ABORTED' && completeBodyUrls.has(failure.url)) recoveredRequests.push({...failure,reason:'preloader consumed exact complete body; browser stream closure reported aborted'});
      else failures.push('REQUEST_FAILED '+failure.url+' '+failure.error);
    }
    for(const failure of httpErrors) failures.push('HTTP_'+failure.status+' '+failure.url);
    const report={url:base,browserPath,scope:'headless isolated browser; not native desktop or human playtest',clicks,messages,failures,recoveredRequests,completedRequests,consumedBodies,dom};
    fs.writeFileSync(path.join(evidence,'W05-browser-qa.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify(report,null,2));
    if (failures.length || messages.some(x=>/SCRIPT ERROR|Parse Error|Failed loading resource|Failed to load resource|Error loading/.test(x.text))) process.exitCode=1;
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
