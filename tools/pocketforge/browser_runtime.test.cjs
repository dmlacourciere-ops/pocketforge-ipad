const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { webkit } = require('playwright');
const runtime = readFileSync(resolve(__dirname,'../../flutter_app/assets/pocketforge/game_runtime.js'),'utf8');

async function game() {
  const browser = await webkit.launch();
  const page = await browser.newPage({viewport:{width:744,height:1133},hasTouch:true});
  await page.addInitScript(runtime);
  await page.setContent('<!doctype html><html><body><button id="play">Play</button><span id="score">0</span><input id="password" type="password" value="do-not-send"><canvas id="game" width="300" height="200" style="display:block"></canvas><script>window.score=0;document.querySelector("#play").onclick=()=>document.querySelector("#score").textContent=String(++window.score);window.keyEvents=[];document.addEventListener("keydown",e=>keyEvents.push([e.key,e.keyCode]));window.pointerEvents=[];document.querySelector("#game").addEventListener("pointerdown",e=>pointerEvents.push([e.clientX,e.clientY]));</script></body></html>');
  // setContent preserves the window; init scripts only run on navigations.
  await page.evaluate(runtime);
  return {browser,page};
}

test('actual WebKit game tools click, key, pointer and inspect the resulting state', async () => {
  const {browser,page}=await game();
  try {
    await page.evaluate(()=>window.__pocketGame.run('click',{selector:'#play'}));
    await page.evaluate(()=>window.__pocketGame.run('key',{key:'ArrowLeft',action:'press'}));
    const point=await page.locator('#game').boundingBox();
    await page.evaluate(({x,y})=>window.__pocketGame.run('pointer',{x,y,action:'down'}),{x:point.x+20,y:point.y+20});
    const state=await page.evaluate(()=>({score:window.score,keys:keyEvents,pointers:pointerEvents,page:window.__pocketGame.run('read')}));
    assert.equal(state.score,1); assert.deepEqual(state.keys,[['ArrowLeft',37]]); assert.equal(state.pointers.length,1);
    const read=await page.evaluate(()=>window.__pocketGame.run('read'));
    assert.equal(read.interactive.find(x=>x.selector==='#password').value,'[redacted]');
    assert.equal(JSON.stringify(read).includes('do-not-send'),false);
  } finally {await browser.close();}
});

test('actual async assertions report passes, failures, exceptions and zero-assertion failure', async () => {
  const {browser,page}=await game();
  try {
    const pass=await page.evaluate(()=>window.__pocketGame.run('test',{script:'await Promise.resolve();assert(document.querySelector("#play").textContent==="Play","button exists");assert(window.score===0,"initial score");'}));
    assert.equal(pass.passed,true); assert.equal(pass.checks.length,2);
    const failure=await page.evaluate(()=>window.__pocketGame.run('test',{script:'assert(false,"intentional failure");throw new Error("test exception");'}));
    assert.equal(failure.passed,false); assert.equal(failure.checks.length,2); assert.match(failure.checks[1].message,/test exception/);
    const empty=await page.evaluate(()=>window.__pocketGame.run('test',{script:'await Promise.resolve(1);'}));
    assert.equal(empty.passed,false); assert.match(empty.checks[0].message,/No assertions/);
    const bounded=await page.evaluate(()=>window.__pocketGame.run('eval',{code:'"x".repeat(100000)'}));
    assert.equal(bounded.truncated,true); assert.ok(bounded.text.length<=63000);
  } finally {await browser.close();}
});

test('opaque iframe RPC observes local game while preventing access to parent storage', async () => {
  const browser=await webkit.launch(); const page=await browser.newPage();
  try {
    await page.goto('about:blank');
    await page.setContent('<iframe sandbox="allow-scripts" style="width:744px;height:600px"></iframe>');
    const document=`<!doctype html><html><body><button id="play">Play</button><script>${runtime}</script><script>window.__pocketGame.installRpc("test-nonce");window.score=0;document.querySelector("#play").onclick=()=>window.score++;</script></body></html>`;
    await page.evaluate(document=>{document;const f=window.document.querySelector('iframe');f.srcdoc=document;},document);
    await page.frames()[1].waitForFunction(()=>!!window.__pocketGame);
    const result=await page.evaluate(()=>new Promise((resolve,reject)=>{
      const frame=document.querySelector('iframe');const timer=setTimeout(()=>reject(Error('RPC timeout')),3000);
      addEventListener('message',function receive(event){if(event.source===frame.contentWindow&&event.data?.nonce==='test-nonce'&&event.data?.id==='1'){clearTimeout(timer);removeEventListener('message',receive);resolve(event.data);}});
      frame.contentWindow.postMessage({channel:'pocketforge-game',nonce:'test-nonce',kind:'request',id:'1',method:'test',payload:{script:'let blocked=false;try{parent.document.body}catch(_){blocked=true};assert(blocked,"parent DOM is inaccessible");document.querySelector("#play").click();assert(window.score===1,"local click updates actual game");'}},'*');
    }));
    assert.equal(result.value.passed,true); assert.equal(result.value.checks.length,2);
  } finally {await browser.close();}
});
