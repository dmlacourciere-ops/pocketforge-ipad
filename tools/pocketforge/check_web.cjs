const { chromium, webkit } = require('playwright');
const { mkdir, writeFile } = require('node:fs/promises');
const path = require('node:path');
const { readFile } = require('node:fs/promises');
const assert = require('node:assert/strict');

(async () => {
  const useWebKit = process.env.POCKETFORGE_BROWSER === 'webkit';
  const browser = await (useWebKit ? webkit : chromium).launch(useWebKit ? { headless: true } : { channel: 'chrome', headless: true });
  const page = await browser.newPage({ viewport: useWebKit ? { width: 744, height: 1133 } : { width: 1133, height: 744 }, deviceScaleFactor: 1 });
  const suffix = useWebKit ? '-webkit' : '';
  const typeInto = async (locator, value) => {
    // WebKit's Flutter semantics text fields need the keyboard event path;
    // filling the mirrored DOM value alone does not update EditableText.
    if (useWebKit) { await locator.click(); await page.waitForTimeout(150); await page.keyboard.type(value); }
    else await locator.fill(value);
  };
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error') errors.push(message.text());
  });
  const source = await readFile(path.resolve(__dirname, '../../flutter_app/assets/pocketforge/starter-game.js'), 'utf8');
  const buggy = source.replace('this.shield -= 1;', 'this.shield -= 0;');
  const repaired = `${source}\nwindow.__pocketforgePersistence = 'repaired-and-saved';\n`;
  assert.notEqual(buggy, source);
  const check = "document.querySelector('#start').click(); window.__gameTest.addObstacle(0,.905); window.__gameTest.advance(.1); assert(window.__gameTest.snapshot().shield===2,'A collision consumes one shield');";
  const calls = [
    { name: 'write', arguments: { path: 'game.js', content: buggy } },
    { name: 'game_preview', arguments: {} },
    { name: 'game_test', arguments: { script: check } },
    { name: 'write', arguments: { path: 'game.js', content: repaired } },
    { name: 'game_preview', arguments: {} },
    { name: 'game_test', arguments: { script: check } },
  ];
  let request = 0, observedFail = false, observedPass = false;
  const toolResults = [];
  await page.route(/^https:\/\/api\.deepseek\.com\/(?:v1\/)?chat\/completions$/, async route => {
    if (route.request().method() === 'OPTIONS') {
      await route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-methods': 'POST, OPTIONS', 'access-control-allow-headers': '*' } });
      return;
    }
    const body = route.request().postDataJSON();
    const results = body.messages.filter(message => message.role === 'tool').map(message => message.content).join('\n');
    if (results.includes('"passed":false')) observedFail = true;
    if (results.includes('"passed":true')) observedPass = true;
    const index = request++;
    toolResults.push({ request: index, results: results.slice(-8000) });
    console.log(`Provider request ${index + 1}: ${calls[index]?.name || 'final response'}`);
    const call = calls[index];
    const delta = call ? { role: 'assistant', tool_calls: [{ index: 0, id: `pf_call_${index}`, type: 'function', function: { name: call.name, arguments: JSON.stringify(call.arguments) } }] }
      : { role: 'assistant', content: 'Mock-provider verification complete: the collision failure was repaired and the real browser retest passed.' };
    const chunk = (value, finish) => JSON.stringify({ id: `pf_reply_${index}`, object: 'chat.completion.chunk', created: 0, model: 'deepseek-flash', choices: [{ index: 0, delta: value, finish_reason: finish }] });
    await route.fulfill({ status: 200, contentType: 'text/event-stream', headers: { 'access-control-allow-origin': '*' },
      body: `data: ${chunk(delta, null)}\n\ndata: ${chunk({}, call ? 'tool_calls' : 'stop')}\n\ndata: [DONE]\n\n` });
  });
  try {
    await page.goto('http://127.0.0.1:8768', { waitUntil: 'networkidle', timeout: 120000 });
    await page.waitForTimeout(4000);
    await page.locator('flt-semantics-placeholder').evaluateAll(elements => elements.forEach(element => element.click()));
    await page.waitForTimeout(1000);
    await page.getByRole('button', { name: 'Model settings', exact: true }).click();
    await typeInto(page.getByRole('textbox', { name: 'API key', exact: true }), 'mock-key-for-pocketforge-e2e');
    await page.getByRole('button', { name: 'Save settings', exact: true }).click();
    await page.getByRole('button', { name: 'Close settings', exact: true }).waitFor({ state: 'hidden', timeout: 20000 });
    await typeInto(page.getByRole('textbox'), 'Verification fixture: run the collision regression test, repair the game, and retest it.');
    await page.getByRole('button', { name: 'Send message', exact: true }).click();
    const deadline = Date.now() + 60000;
    while (request < 7 && Date.now() < deadline) await page.waitForTimeout(250);
    await page.waitForTimeout(1000);
    assert.equal(observedFail, true, 'The actual app must send the failed WebKit/Chromium game assertion back to the provider');
    assert.equal(observedPass, true, 'The actual app must send a passing assertion after rewriting/reloading the source');
    assert.equal(request, 7, 'Six real tools and a final model response should settle');
    const game = page.frames().find(frame => frame !== page.mainFrame() && frame.url() !== 'about:blank');
    assert.ok(game, 'A real game frame must be mounted');
    assert.equal(await game.locator('#race').count(), 1);
    await mkdir(path.resolve(__dirname, '../../artifacts/test-results'), { recursive: true });
    await page.screenshot({ path: path.resolve(__dirname, `../../artifacts/test-results/pocketforge-live-web${suffix}.png`) });
    const snapshot = await page.locator('body').innerText();
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(2000);
    await page.locator('flt-semantics-placeholder').evaluateAll(elements => elements.forEach(element => element.click()));
    await page.getByRole('button', { name: 'Model settings', exact: true }).click();
    await page.getByRole('textbox', { name: 'API key', exact: true }).waitFor({ state: 'visible', timeout: 15000 });
    assert.equal(await page.getByRole('textbox', { name: 'API key', exact: true }).count(), 1, 'A browser reload must discard the session-only provider key');
    assert.equal(await page.getByRole('button', { name: 'Remove key', exact: true }).count(), 0);
    await page.getByRole('button', { name: 'Close settings', exact: true }).click();
    await page.getByRole('button', { name: 'Run project', exact: true }).click();
    let restored;
    const restoreDeadline = Date.now() + 15000;
    while (Date.now() < restoreDeadline) {
      const frame = page.frames().find(frame => frame !== page.mainFrame() && frame.url() !== 'about:blank');
      if (frame && await frame.evaluate(() => window.__pocketforgePersistence).catch(() => null) === 'repaired-and-saved') { restored = true; break; }
      await page.waitForTimeout(200);
    }
    assert.equal(restored, true, 'Actual project source must persist in IndexedDB across app reload');
    assert.equal(request, 7, 'Reopening and running the saved game must not call the model');
    const report = { title: await page.title(), requests: request, observedFail, observedPass, projectPersisted: true, browserKeyDiscarded: true, text: snapshot.slice(0, 14000), frames: page.frames().map(frame => frame.url()), errors, toolResults };
    await writeFile(path.resolve(__dirname, `../../artifacts/test-results/pocketforge-web-e2e${suffix}.json`), JSON.stringify(report, null, 2));
    console.log(JSON.stringify({ title: report.title, requests: request, observedFail, observedPass, errors }, null, 2));
    assert.deepEqual(errors, []);
    await writeFile(path.resolve(__dirname, '../../artifacts/test-results/pocketforge-live-web-errors.json'), JSON.stringify(errors, null, 2));
  } catch (error) {
    await mkdir(path.resolve(__dirname, '../../artifacts/test-results'), { recursive: true });
    await page.screenshot({ path: path.resolve(__dirname, '../../artifacts/test-results/pocketforge-web-failure.png') });
    const report = { text: (await page.locator('body').innerText()).slice(0, 10000), requests: request, errors, toolResults };
    await writeFile(path.resolve(__dirname, '../../artifacts/test-results/pocketforge-web-e2e-failure.json'), JSON.stringify(report, null, 2));
    console.error(JSON.stringify({ requests: request, errors, lastResult: toolResults.at(-1)?.results.slice(-1500) }, null, 2));
    throw error;
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
