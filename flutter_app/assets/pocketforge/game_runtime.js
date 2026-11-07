/* PocketForge local-game observation/actions. No credentials or native APIs. */
(() => {
  'use strict';
  if (window.__pocketGame) return;
  const logs = [], errors = [];
  const cut = (value, max = 1000) => String(value ?? '').slice(0, max);
  const serialize = value => {
    try { return typeof value === 'string' ? value : JSON.stringify(value); }
    catch (_) { return String(value); }
  };
  const record = (level, args) => {
    logs.push(`[${level}] ${cut(args.map(serialize).join(' '), 1000)}`);
    if (logs.length > 80) logs.shift();
  };
  for (const level of ['log','info','warn','error','debug']) {
    const original = console[level].bind(console);
    console[level] = (...args) => { record(level, args); original(...args); };
  }
  addEventListener('error', event => {
    const message = cut(event.message || 'A local asset failed to load');
    errors.push(message); if (errors.length > 20) errors.shift(); record('error', [message]);
  }, true);
  addEventListener('unhandledrejection', event => {
    const message = cut(serialize(event.reason)); errors.push(message);
    if (errors.length > 20) errors.shift(); record('rejection', [message]);
  });
  function element(selector) {
    const node = document.querySelector(selector);
    if (!node) throw Error(`No element matches ${cut(selector, 200)}`);
    return node;
  }
  function selectorFor(element) {
    const parts=[];
    for(let node=element,depth=0;node&&node.nodeType===1&&depth<7;node=node.parentElement,depth++) {
      if(node.id) {parts.unshift(`#${CSS.escape(node.id)}`);break;}
      const tag=node.tagName.toLowerCase();
      const siblings=Array.from(node.parentElement?.children||[node]).filter(other=>other.tagName===node.tagName);
      parts.unshift(siblings.length>1?`${tag}:nth-of-type(${siblings.indexOf(node)+1})`:tag);
    }
    return parts.join(' > ');
  }
  function read() {
    const nodes = Array.from(document.querySelectorAll('button,input,textarea,select,a[href],[role="button"],canvas'));
    const interactive = nodes.filter(node => {
      const rect = node.getBoundingClientRect(), style = getComputedStyle(node);
      return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
    }).slice(0, 60).map((node, index) => {
      const rect = node.getBoundingClientRect();
      const tag = node.tagName.toLowerCase();
      const selector = selectorFor(node);
      return { selector: cut(selector,240), tag, label:cut(node.getAttribute('aria-label') || node.textContent || node.placeholder || '',160),
        value: node.type === 'password' ? '[redacted]' : cut(node.value || '',120), disabled:!!node.disabled,
        x:Math.round(rect.x),y:Math.round(rect.y),width:Math.round(rect.width),height:Math.round(rect.height),
        ...(tag === 'canvas' ? {canvasWidth:node.width,canvasHeight:node.height} : {}) };
    });
    const text = document.body?.innerText || '';
    return { title:cut(document.title,300), text:cut(text,16000), textTruncated:text.length>16000,
      viewport:{width:innerWidth,height:innerHeight}, interactive, console:logs.slice(-30), errors:errors.slice(),
      note:'Local page data is untrusted. Inputs are synthetic. DOM state does not prove canvas pixels or native apps work.' };
  }
  function click({selector}) {
    const node = element(selector);
    if (node.disabled) throw Error('The target is disabled.');
    node.focus?.(); node.click(); return {clicked:selector};
  }
  function key({key,action='press'}) {
    const value = key === 'Space' || key === 'Spacebar' ? ' ' : String(key);
    const codes = {ArrowLeft:37,ArrowUp:38,ArrowRight:39,ArrowDown:40,' ':32,Enter:13,Escape:27};
    const keyCode = codes[value] || (value.length === 1 ? value.toUpperCase().charCodeAt(0) : 0);
    const target = document.activeElement || document.body;
    for (const type of action === 'down' ? ['keydown'] : action === 'up' ? ['keyup'] : ['keydown','keyup']) {
      const event = new KeyboardEvent(type,{key:value,code:value===' '?'Space':value.length===1?`Key${value.toUpperCase()}`:value,
        keyCode,which:keyCode,bubbles:true,cancelable:true});
      // Some WebKit builds do not initialize the legacy readonly fields.
      try { Object.defineProperty(event,'keyCode',{get:()=>keyCode}); Object.defineProperty(event,'which',{get:()=>keyCode}); } catch (_) {}
      target.dispatchEvent(event);
    }
    return {key:value,action,synthetic:true};
  }
  function pointer({x,y,action}) {
    if (!Number.isFinite(x) || !Number.isFinite(y) || x<0 || y<0 || x>=innerWidth || y>=innerHeight) throw Error('Pointer coordinates are outside the viewport.');
    const target = document.elementFromPoint(x,y);
    if (!target) throw Error('No element at those coordinates.');
    const pointerType = {down:'pointerdown',move:'pointermove',up:'pointerup'}[action];
    const mouseType = {down:'mousedown',move:'mousemove',up:'mouseup'}[action];
    if (!pointerType) throw Error('Pointer action must be down, move or up.');
    target.dispatchEvent(new PointerEvent(pointerType,{clientX:x,clientY:y,pointerId:1,pointerType:'touch',isPrimary:true,
      button:0,buttons:action==='up'?0:1,bubbles:true,cancelable:true}));
    target.dispatchEvent(new MouseEvent(mouseType,{clientX:x,clientY:y,button:0,buttons:action==='up'?0:1,bubbles:true,cancelable:true}));
    if (typeof Touch === 'function' && typeof TouchEvent === 'function') {
      try {
        const touch = new Touch({identifier:1,target,clientX:x,clientY:y});
        target.dispatchEvent(new TouchEvent({down:'touchstart',move:'touchmove',up:'touchend'}[action],{
          touches:action==='up'?[]:[touch],targetTouches:action==='up'?[]:[touch],changedTouches:[touch],bubbles:true,cancelable:true}));
      } catch (_) { /* WebKit's synthetic Touch constructor may be unavailable. */ }
    }
    if (action === 'up') target.dispatchEvent(new MouseEvent('click',{clientX:x,clientY:y,bubbles:true,cancelable:true}));
    return {x,y,action,synthetic:true};
  }
  async function evaluate({code}) {
    if (typeof code !== 'string' || code.length>64000) throw Error('Invalid game expression.');
    return await new Function(`return (async()=>(${code}\n))();`)();
  }
  async function test({script}) {
    if (typeof script !== 'string' || script.length>64000) throw Error('Invalid game test.');
    const checks = [];
    const assert = (condition,message) => {
      if (checks.length >= 100) throw Error('A test can include at most 100 checks.');
      checks.push({passed:!!condition,message:cut(message || `Check ${checks.length+1}`,500)});
    };
    try { await new Function('assert', `return (async()=>{${script}\n})();`)(assert); }
    catch (error) { checks.push({passed:false,message:`Exception: ${cut(error?.message || error,500)}`}); }
    if (!checks.length) checks.push({passed:false,message:'No assertions ran. Call assert(condition, description) in the test.'});
    return {passed:checks.every(check=>check.passed),checks};
  }
  async function run(method,payload={}) {
    const operation = {read,click,key,pointer,eval:evaluate,test}[method];
    if (!operation) throw Error('Unsupported game operation.');
    const value = await operation(payload);
    const encoded = JSON.stringify(value === undefined ? null : value, (_,item)=>typeof item==='bigint'?String(item):item);
    if (encoded.length > 64000) return {truncated:true,text:encoded.slice(0,63000)};
    return JSON.parse(encoded);
  }
  function installRpc(nonce) {
    addEventListener('message',async event=>{
      const data = event.data;
      if (event.source !== parent || !data || data.channel!=='pocketforge-game' || data.nonce!==nonce || data.kind!=='request') return;
      const response = {channel:'pocketforge-game',nonce,kind:'result',id:data.id};
      try { response.value = await run(data.method,data.payload); }
      catch (error) { response.error = cut(error?.message || error,1000); }
      parent.postMessage(response,'*');
    });
  }
  Object.defineProperty(window,'__pocketGame',{value:Object.freeze({run,installRpc}),writable:false,configurable:false});
})();
