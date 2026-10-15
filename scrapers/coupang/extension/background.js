// Coupang snapshots: the Chrome extension that collects the Coupang pages for the Double 11 study.
//
// At each run time of the study (data-collection-spec.md, section 9.1) it opens Coupang's home
// page in a minimised window of this browser, requests every Coupang product page in the product
// table from that page, at the spec's pace, and saves each response body, gzip-compressed, to
// Downloads/coupang-snapshots/<run date>_<run time>/, with the product table it used
// (products.csv) and a record of the run (run.json). `Rscript scrapers/coupang/scrape_coupang.R
// --saved` turns the saved runs into the spec's CSV files. Each run is reported to Healthchecks.io
// when a ping URL is set. A test run does the same with test_products.csv, which comes with the
// extension, saves to Downloads/coupang-snapshots-test/ and is not reported.
// scrapers/coupang/README.md explains why Coupang is collected this way.

'use strict';

importScripts('lib.js');

const SITE = 'https://www.tw.coupang.com/';
const SAVE_DIR = 'coupang-snapshots';
const TEST_DIR = 'coupang-snapshots-test';
const TEST_TABLE = 'test_products.csv';

const PACE_MS = 5000;           // NFR-1: gap between page requests, retries included
const TIMEOUT_MS = 30000;       // 8.2: per request
const RETRY_WAIT_MS = 60000;    // 8.2: wait before the one retry, and before each block workaround
const SETTLE_MS = 5000;         // time on the home page after it has loaded, as a visitor would stay
const MAX_BLOCKED_STREAK = 3;   // after this many products in a row end blocked, skip the workarounds
const HISTORY_LENGTH = 30;      // finished runs listed in the popup

// Section 7.3: Akamai's Access Denied page and JavaScript check, and Coupang's own 403 page.
const BLOCK_PATTERN = '<title>Access Denied</title>|errors\\.edgesuite\\.net|id="error403"|sec-if-cpt-container';
const PRODUCT_PATTERN = '"@type"\\s*:\\s*"Product"';

const store = chrome.storage.local;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

let current = null;  // the run in progress in this service worker, if any
const ready = recoverInterruptedRun();

chrome.runtime.onInstalled.addListener(() => ready.then(schedule));
chrome.runtime.onStartup.addListener(() => ready.then(schedule));
chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === 'run') ready.then(schedule);
});
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  const kind = {'run-now': 'manual', 'run-test': 'test'}[message?.command];
  if (!kind) return false;
  ready.then(() => startRun(kind)).then(reply, e => reply({error: e.message}));
  return true;
});

// ---- Schedule ------------------------------------------------------------------------------------

// Sets the alarm for the next run time, and starts the run that is due now, if any.
async function schedule() {
  const now = Date.now();
  const next = nextSlot(now);
  if (next === null) await chrome.alarms.clear('run');
  else await chrome.alarms.create('run', {when: next});
  const {lastSlot = 0, history = []} = await store.get(['lastSlot', 'history']);
  if (!current) showResult(history);
  const due = dueSlot(now, lastSlot);
  if (due !== null) await startRun('scheduled', due);
}

// Starts a run in the background. Returns {stamp}, or {error} when it cannot start.
async function startRun(kind, slot = null) {
  if (current) return {error: `A run is still going (started ${current.started_at}).`};
  const now = Date.now();
  const run = {
    format: 1, stamp: runStamp(now), kind, slot: slot === null ? null : taiwanTime(slot),
    started_ms: now, started_at: taiwanTime(now), state: 'running', products: [], skipped: [],
  };
  current = run;
  const {history = []} = await store.get('history');
  if (history.some(past => past.stamp === run.stamp && saveDir(past.kind) === saveDir(kind))) {
    // FR-4: one run per minute, so a run's folder and files are never overwritten.
    current = null;
    return {error: 'A run already started this minute. Try again in a minute.'};
  }
  if (slot !== null) await store.set({lastSlot: slot});
  await store.set({current: run});
  collect(run).finally(() => {
    current = null;
    schedule();
  });
  return {stamp: run.stamp};
}

// ---- One run -------------------------------------------------------------------------------------

async function collect(run) {
  const ctx = {windowId: null, tabId: null, lastRequest: 0, blockedStreak: 0};
  // Keeps the service worker, and the computer, awake until the run is over.
  const keepAlive = setInterval(() => chrome.runtime.getPlatformInfo(), 20000);
  let config = {pingUrl: '', pingUrlExtra: ''};
  try {
    config = await settings();
    chrome.power.requestKeepAwake('system');
    await chrome.downloads.setUiOptions({enabled: false}).catch(() => {});
    setBadge('run');
    run.table_url = run.kind === 'test' ? TEST_TABLE : PRODUCT_TABLE_URL;
    run.browser = navigator.userAgent;
    run.extension_version = chrome.runtime.getManifest().version;
    await ping(pingUrlFor(run, config), '/start', `coupang ${run.stamp} started`);
    const table = await loadProductTable(run.kind === 'test');
    if (table.note) run.table_note = table.note;
    run.folder = folderOf(await saveFile(run, 'products.csv', 'text/csv', base64Text(table.text)));
    const {targets, skipped} = selectProducts(table.text);
    run.skipped = skipped;
    run.target_count = targets.length;
    await store.set({current: run});
    if (targets.length > 0) {
      await openSite(ctx);
      run.home = ctx.home;
    }
    for (const target of targets) {
      await collectProduct(run, ctx, target);
      await store.set({current: run});
    }
    run.state = 'finished';
  } catch (e) {
    run.state = 'failed';
    run.error = e.message;
  } finally {
    clearInterval(keepAlive);
    await finishRun(run, ctx.windowId, config);
  }
}

// Requests one product page, with the retry and block workarounds of section 8.2, in the same
// order as scrape_product() in scrape_coupang.R. Every response body is saved.
async function collectProduct(run, ctx, target) {
  const entry = {product_id: target.product_id, item_id: target.item_id, url: target.url, attempts: []};
  run.products.push(entry);
  const attempt = async () => {
    const wait = ctx.lastRequest + PACE_MS - Date.now();
    if (wait > 0) await sleep(wait);
    const sent = Date.now();
    const response = await requestPage(ctx, target.url);
    ctx.lastRequest = Date.now();
    const record = {
      sent_ms: sent, sent_at: taiwanTime(sent), status: response.status ?? null,
      final_url: response.finalUrl ?? null, error: response.error ?? null, bytes: response.bytes ?? null,
      product_page: Boolean(response.productPage), block_page: Boolean(response.blockPage), file: null,
    };
    if (response.gzip) {
      const file = `${target.item_id}_try${entry.attempts.length + 1}.html.gz`;
      try {
        await saveFile(run, file, 'application/gzip', response.gzip);
        record.file = file;
      } catch (e) {
        record.error = e.message;
      }
    }
    entry.attempts.push(record);
    return judgeResponse(record);
  };

  let verdict = await attempt();
  if (verdict.retry) {
    await sleep(RETRY_WAIT_MS);
    verdict = await attempt();
  }
  // A block is worked around before it counts: back off, then come back through the home page
  // (the R scraper starts a fresh browser instead, which this browser must not do). Once several
  // products in a row end blocked, each product gets one request only.
  if (verdict.blocked && ctx.blockedStreak < MAX_BLOCKED_STREAK) {
    await sleep(RETRY_WAIT_MS);
    verdict = await attempt();
    if (verdict.blocked) {
      await visitHome(ctx);
      await sleep(RETRY_WAIT_MS);
      verdict = await attempt();
    }
  }
  ctx.blockedStreak = verdict.blocked ? ctx.blockedStreak + 1 : 0;
}

async function finishRun(run, windowId, config) {
  run.finished_ms = Date.now();
  run.finished_at = taiwanTime(run.finished_ms);
  if (windowId !== null && windowId !== undefined) await chrome.windows.remove(windowId).catch(() => {});
  try {
    const saved = await saveFile(run, 'run.json', 'application/json', base64Text(JSON.stringify(run, null, 1)));
    run.folder = run.folder || folderOf(saved);
  } catch (e) {
    run.state = 'failed';
    run.error = [run.error, e.message].filter(Boolean).join('; ');
  }
  const summary = summarise(run);
  summary.ping_error = await ping(pingUrlFor(run, config), summary.ok ? '' : '/fail',
    `${summary.line}\n${summary.folder || ''}`);
  const {history = []} = await store.get('history');
  const updated = [summary, ...history].slice(0, HISTORY_LENGTH);
  await store.set({history: updated});
  await store.remove(['current', 'runWindow']);
  await chrome.downloads.setUiOptions({enabled: true}).catch(() => {});
  chrome.power.releaseKeepAwake();
  showResult(updated);
}

// A run whose service worker stopped (Chrome was closed, crashed or updated during the run) is
// finished when the extension next starts: run.json records what was saved, and the run is
// reported as failed.
async function recoverInterruptedRun() {
  const {current: orphan, runWindow = null} = await store.get(['current', 'runWindow']);
  if (!orphan) return;
  orphan.state = 'interrupted';
  orphan.error = 'Chrome or the extension stopped during the run';
  await finishRun(orphan, runWindow, await settings());
}

// ---- The Coupang tab -----------------------------------------------------------------------------

// Opens Coupang's home page in a new minimised window, as a visitor arriving at the site.
async function openSite(ctx) {
  const win = await chrome.windows.create({url: SITE, focused: false, state: 'minimized'});
  ctx.windowId = win.id;
  ctx.tabId = win.tabs[0].id;
  await store.set({runWindow: win.id});
  ctx.home = await settle(ctx.tabId);
  ctx.lastRequest = Date.now();
}

async function visitHome(ctx) {
  try {
    await chrome.tabs.update(ctx.tabId, {url: SITE});
    ctx.home = await settle(ctx.tabId);
    ctx.lastRequest = Date.now();
  } catch (e) {
    await openSite(ctx);
  }
}

// Waits for the tab to finish loading, stays a moment, and reports whether it shows a block page.
async function settle(tabId) {
  const deadline = Date.now() + TIMEOUT_MS;
  let loaded = false;
  await sleep(500);
  while (!loaded && Date.now() < deadline) {
    const tab = await chrome.tabs.get(tabId).catch(() => null);
    if (!tab) break;
    loaded = tab.status === 'complete';
    if (!loaded) await sleep(500);
  }
  await sleep(SETTLE_MS);
  const [injection] = await chrome.scripting.executeScript({
    target: {tabId}, args: [BLOCK_PATTERN],
    func: pattern => new RegExp(pattern, 'i').test(document.documentElement.outerHTML),
  }).catch(() => [null]);
  return {loaded, blocked: injection?.result ?? null};
}

// Requests `url` from the run's Coupang tab, reopening the tab if it was closed.
async function requestPage(ctx, url) {
  try {
    const tab = ctx.tabId === null ? null : await chrome.tabs.get(ctx.tabId).catch(() => null);
    if (!tab) await openSite(ctx);
    else if (!(tab.url || '').startsWith(SITE)) await visitHome(ctx);
    const [injection] = await withTimeout(chrome.scripting.executeScript({
      target: {tabId: ctx.tabId}, world: 'ISOLATED', func: requestFromPage,
      args: [url, TIMEOUT_MS, BLOCK_PATTERN, PRODUCT_PATTERN],
    }), TIMEOUT_MS + 15000, 'the Coupang tab did not answer');
    return injection?.result ?? {error: 'the Coupang tab returned nothing'};
  } catch (e) {
    return {error: e.message};
  }
}

// Runs inside the Coupang tab: requests `url` as the page itself would, with this browser's
// cookies, and returns the status and the response body, gzip-compressed and base64-encoded.
// It must not use anything outside itself, because Chrome copies it into the page.
async function requestFromPage(url, timeoutMs, blockPattern, productPattern) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {credentials: 'include', signal: controller.signal});
    const body = new Uint8Array(await response.arrayBuffer());
    const text = new TextDecoder().decode(body);
    const zipped = new Uint8Array(await new Response(
      new Blob([body]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer());
    let binary = '';
    for (let i = 0; i < zipped.length; i += 0x8000) binary += String.fromCharCode(...zipped.subarray(i, i + 0x8000));
    return {
      status: response.status, finalUrl: response.url, bytes: body.length, gzip: btoa(binary),
      blockPage: new RegExp(blockPattern, 'i').test(text), productPage: new RegExp(productPattern).test(text),
    };
  } catch (e) {
    return {error: e.name === 'AbortError' ? 'timeout' : String(e.message || e)};
  } finally {
    clearTimeout(timer);
  }
}

// ---- Files ---------------------------------------------------------------------------------------

// The study's product table from GitHub, or the last copy downloaded when GitHub cannot be
// reached; for a test run, the test table that comes with the extension.
async function loadProductTable(test) {
  if (test) return {text: await (await fetch(chrome.runtime.getURL(TEST_TABLE))).text(), note: null};
  const url = PRODUCT_TABLE_URL;
  try {
    const response = await fetch(url, {cache: 'no-store'});
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    await store.set({tableCache: {url, text, at: Date.now()}});
    return {text, note: null};
  } catch (e) {
    const {tableCache} = await store.get('tableCache');
    if (tableCache && tableCache.url === url) {
      return {text: tableCache.text,
        note: `could not download the product table (${e.message}); used the copy from ${taiwanTime(tableCache.at)}`};
    }
    throw new Error(`could not download the product table ${url} (${e.message})`);
  }
}

// Saves base64 `data` as `name` in the run's folder, Downloads/<save dir>/<stamp>/; returns the
// file's full path.
async function saveFile(run, name, mimeType, data) {
  const id = await chrome.downloads.download({
    url: `data:${mimeType};base64,${data}`, filename: `${saveDir(run.kind)}/${run.stamp}/${name}`,
    conflictAction: 'overwrite', saveAs: false,
  });
  const item = await downloadDone(id);
  chrome.downloads.erase({id});  // removes the entry from Chrome's download list; the file stays
  if (item.state !== 'complete') throw new Error(`could not save ${name} (${item.error || item.state})`);
  return item.filename;
}

const saveDir = kind => kind === 'test' ? TEST_DIR : SAVE_DIR;

function downloadDone(id) {
  return new Promise(resolve => {
    let timer = null;
    const finish = item => {
      clearTimeout(timer);
      chrome.downloads.onChanged.removeListener(listener);
      resolve(item);
    };
    const check = async () => {
      const [item] = await chrome.downloads.search({id});
      if (!item || item.state !== 'in_progress') finish(item || {state: 'missing'});
    };
    const listener = delta => {
      if (delta.id === id && delta.state) check();
    };
    timer = setTimeout(() => finish({state: 'timed out'}), TIMEOUT_MS);
    chrome.downloads.onChanged.addListener(listener);
    check();
  });
}

const folderOf = path => path.replace(/[\\/][^\\/]*$/, '');

// ---- Settings, status and reports ----------------------------------------------------------------

async function settings() {
  const saved = await store.get(['pingUrl', 'pingUrlExtra']);
  return {pingUrl: saved.pingUrl || '', pingUrlExtra: saved.pingUrlExtra || ''};
}

// The Healthchecks.io check to report to: the one for the 18:07 and 23:07 runs when it is set.
// Test runs are not reported.
function pingUrlFor(run, config) {
  if (run.kind === 'test') return '';
  return isExtraSlot(run.slot) && config.pingUrlExtra ? config.pingUrlExtra : config.pingUrl;
}

// Reports to Healthchecks.io. Returns null, or why the report did not get through.
async function ping(url, suffix, body) {
  if (!url) return null;
  try {
    const response = await fetch(url.replace(/\/+$/, '') + suffix, {method: 'POST', body, cache: 'no-store'});
    return response.ok ? null : `HTTP ${response.status}`;
  } catch (e) {
    return e.message;
  }
}

// A red "!" on the icon while the last run of the study (test runs aside) did not get every page.
function showResult(history) {
  const last = history.find(past => past.kind !== 'test');
  setBadge(last && !last.ok ? '!' : '');
}

function setBadge(text) {
  chrome.action.setBadgeText({text});
  if (text) chrome.action.setBadgeBackgroundColor({color: text === '!' ? '#c5221f' : '#1a73e8'});
}

function withTimeout(promise, ms, message) {
  let timer = null;
  const timeout = new Promise((resolve, reject) => {
    timer = setTimeout(() => reject(new Error(message)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
