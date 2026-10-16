// Helpers shared by background.js and popup.js. Nothing here calls Chrome, so the file can also be
// loaded in Node to check the schedule and the product selection.

'use strict';

const PRODUCT_TABLE_URL =
  'https://raw.githubusercontent.com/Bakuretsu05/pba-project-the-janggals/main/products/products.csv';

// Run times, Taiwan time (data-collection-spec.md, section 9.1).
const SCHEDULE = {
  first: '2026-10-19',
  last: '2026-11-25',
  daily: ['15:07'],
  extraDays: ['2026-11-10', '2026-11-11', '2026-11-12'],
  extraTimes: ['18:07', '23:07'],
};

const INPUT_COLUMNS = ['product_id', 'brand', 'model', 'category', 'momo_url', 'pchome_url',
  'coupang_url', 'biggo_url_momo', 'biggo_url_pchome', 'biggo_url_coupang'];

const COUPANG_LINK = /^https?:\/\/([a-z0-9-]+\.)*coupang\.com(:[0-9]+)?([/?#]|$)/i;

// ---- Time ------------------------------------------------------------------------------------

// Taiwan time (UTC+8 all year) as "YYYY-MM-DD HH:MM:SS".
function taiwanTime(ms) {
  return new Date(ms + 8 * 3600000).toISOString().slice(0, 19).replace('T', ' ');
}

// "YYYY-MM-DD_HHMM": the run date and run time (spec section 4) of a run started at `ms`.
function runStamp(ms) {
  const t = taiwanTime(ms);
  return `${t.slice(0, 10)}_${t.slice(11, 13)}${t.slice(14, 16)}`;
}

// Every scheduled run time, as epoch milliseconds, in order.
function slotTimes() {
  const slots = [];
  for (let day = Date.parse(`${SCHEDULE.first}T00:00:00Z`); ; day += 86400000) {
    const date = new Date(day).toISOString().slice(0, 10);
    if (date > SCHEDULE.last) break;
    const times = SCHEDULE.daily.concat(SCHEDULE.extraDays.includes(date) ? SCHEDULE.extraTimes : []);
    for (const time of times) slots.push(Date.parse(`${date}T${time}:00+08:00`));
  }
  return slots.sort((a, b) => a - b);
}

function nextSlot(now) {
  const next = slotTimes().find(t => t > now);
  return next === undefined ? null : next;
}

// The run time to start now: the latest one that has passed, if it has not been started yet and
// is on today's date (Taiwan time). A run time missed because Chrome was closed or the computer
// was off is made up later that day, never on a later day.
function dueSlot(now, lastSlot) {
  const due = slotTimes().filter(t => t <= now).pop();
  if (due === undefined || due <= (lastSlot || 0)) return null;
  return taiwanTime(due).slice(0, 10) === taiwanTime(now).slice(0, 10) ? due : null;
}

// True for the 18:07 and 23:07 runs of Nov 10-12. `slot` is a run's slot field (Taiwan time).
function isExtraSlot(slot) {
  return Boolean(slot) && !SCHEDULE.daily.includes(slot.slice(11, 16));
}

// ---- The product table (spec section 6) --------------------------------------------------------

// Rows of a CSV file (RFC 4180: quoted fields may hold commas, quotes and line breaks). Blank lines
// are dropped, as read.csv() does.
function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  text = text.replace(/^﻿/, '');
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c !== '"') field += c;
      else if (text[i + 1] === '"') { field += '"'; i++; }
      else quoted = false;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (c !== '\r') field += c;
  }
  if (field !== '' || row.length > 0) { row.push(field); rows.push(row); }
  return rows.filter(r => r.some(cell => cell.trim() !== ''));
}

// The itemId query parameter of a coupang.com link, or null. Same rule as extract_item_id() in
// scrape_coupang.R.
function itemIdOf(url) {
  url = url.trim();
  if (!COUPANG_LINK.test(url)) return null;
  const query = url.includes('?') ? url.replace(/^[^?]*\?/, '') : '';
  for (const pair of query.replace(/#.*$/, '').split('&amp;').join('&').split('&')) {
    const kv = pair.split('=');
    if (kv.length === 2 && kv[0] === 'itemId' && /^[0-9]+$/.test(kv[1])) return kv[1];
  }
  return null;
}

// The products to request, in file order, and the rows left out with the reason (section 6.3).
// Same rules as select_products() in scrape_coupang.R, which judges the rows again on import.
function selectProducts(text) {
  const rows = parseCsv(text);
  if (rows.length === 0) throw new Error('the product table is empty');
  const header = rows[0].map(name => name.trim());
  const missing = INPUT_COLUMNS.filter(name => !header.includes(name));
  if (missing.length > 0) throw new Error(`the product table is missing column(s): ${missing.join(', ')}`);
  const cell = (row, name) => (row[header.indexOf(name)] || '').trim();
  const ids = rows.slice(1).map(row => cell(row, 'product_id'));
  const targets = [];
  const skipped = [];
  rows.slice(1).forEach((row, i) => {
    const url = cell(row, 'coupang_url');
    if (!url) return;
    const productId = ids[i];
    const itemId = itemIdOf(url);
    let problem = null;
    if (!productId) problem = 'product_id is empty';
    else if (ids.indexOf(productId) !== ids.lastIndexOf(productId)) problem = 'product_id appears more than once';
    else if (!COUPANG_LINK.test(url)) problem = 'coupang_url is not a coupang.com link';
    else if (!itemId) problem = 'no itemId found in coupang_url';
    const entry = {product_id: productId, item_id: itemId, url};
    if (problem) skipped.push({...entry, problem});
    else targets.push(entry);
  });
  return {targets, skipped};
}

// ---- Responses and runs ----------------------------------------------------------------------------

// Whether a response gets the one retry of section 8.2 (429, 5xx, timeout or connection error),
// and whether it is a block (403, 429 or a block page). Same rules as judge_page() in R.
function judgeResponse(response) {
  if (response.status === null || response.status === undefined) return {retry: true, blocked: false};
  if (response.status === 429) return {retry: true, blocked: true};
  if (response.status === 403 || response.block_page) return {retry: false, blocked: true};
  return {retry: response.status >= 500, blocked: false};
}

// What a run amounts to, judged on the last response for each product: one line in the style of
// the spec's summary line (FR-8), and `ok`, true when every product was answered with a page that
// is not a block page and at least one of them is a product page. The CSV's own statuses come
// later, from the R import.
function summarise(run) {
  const counts = {'product page': 0, 'other page': 0, 'blocked': 0, 'HTTP error': 0,
    'no response': 0, 'not requested': 0, 'bad input': (run.skipped || []).length};
  const products = run.products || [];
  for (const product of products) {
    const last = product.attempts[product.attempts.length - 1];
    if (!last) counts['not requested']++;
    else if (last.status === null || last.status === undefined) counts['no response']++;
    else if (judgeResponse(last).blocked) counts.blocked++;
    else if (last.status >= 400) counts['HTTP error']++;
    else if (last.product_page) counts['product page']++;
    else counts['other page']++;
  }
  const total = Math.max(run.target_count || 0, products.length);
  counts['not requested'] += total - products.length;
  const parts = Object.entries(counts).filter(([, n]) => n > 0).map(([kind, n]) => `${kind} ${n}`);
  const failed = counts.blocked + counts['HTTP error'] + counts['no response'] + counts['not requested'];
  const ok = run.state === 'finished' && counts['product page'] > 0 && failed === 0;
  const state = run.error ? `${run.state}: ${run.error}` : run.state;
  return {
    stamp: run.stamp, kind: run.kind, state: run.state, ok, counts, folder: run.folder || null,
    line: `coupang ${run.stamp} (${run.kind}): ${total} products | ${parts.join(', ') || 'nothing requested'} | ${state}`,
  };
}

// Base64 of the UTF-8 bytes of `text`, for a data: URL.
function base64Text(text) {
  const bytes = new TextEncoder().encode(text);
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

if (typeof module !== 'undefined') {
  module.exports = {PRODUCT_TABLE_URL, SCHEDULE, taiwanTime, runStamp, slotTimes, nextSlot, dueSlot,
    isExtraSlot, parseCsv, itemIdOf, selectProducts, judgeResponse, summarise, base64Text};
}
