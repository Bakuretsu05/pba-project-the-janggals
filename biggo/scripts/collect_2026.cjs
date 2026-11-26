#!/usr/bin/env node
// 2026 BigGo price history (deliverable D11). Run from the repository root.
//
//   node biggo/scripts/collect_2026.cjs targets              lookups for the browser runner, as JSON
//   node biggo/scripts/collect_2026.cjs import <bundle.json> split a browser_runner_2026.js export
//                                                            into biggo/raw/2026/ (gitignored)
//   node biggo/scripts/collect_2026.cjs rebuild              write the 2026 outputs from biggo/raw/2026/
//
// rebuild writes data/source/biggo_price_changes_2026.csv (spec section 11 columns),
// biggo/records/collection_status_2026.csv, biggo/records/verification_2026.csv and the 2026 rows
// of biggo/records/history_coverage.csv. It never touches the 2025 change points or 2025 coverage rows.
// The histories are fetched in a signed-in biggo.com.tw tab by browser_runner_2026.js (spec section 3).
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const c = require('./collect_2025.cjs');

const ROOT = c.ROOT;
const RECORDS = path.join(ROOT, 'biggo', 'records');
const RAW = path.join(ROOT, 'biggo', 'raw', '2026');
const PRICES = path.join(ROOT, 'data', 'source', 'biggo_price_changes_2026.csv');
const STATUS = path.join(RECORDS, 'collection_status_2026.csv');
const VERIFY = path.join(RECORDS, 'verification_2026.csv');
const COVERAGE = path.join(RECORDS, 'history_coverage.csv');
const SHOPS = {momo: 'tw_pec_momoshop', pchome: 'tw_ec_pchome24h', coupang: 'tw_pec_coupang'};
const START = Date.parse('2026-09-01T00:00:00+08:00');
const END = Date.parse('2026-11-26T00:00:00+08:00');
const LAST_SLOT = Date.parse('2026-11-25T15:07:00+08:00');
const ENTERED_BY = 'Marvin';
const STATUS_COLUMNS = ['product_id', 'platform', 'history_id', 'status', 'rows', 'baseline', 'first_point_tw',
  'last_point_tw', 'current_price', 'title', 'note'];
const COVERAGE_COLUMNS = ['product_id', 'platform', 'coverage_start', 'coverage_end', 'note'];
const VERIFY_COLUMNS = ['product_id', 'platform', 'method', 'result', 'first_rows', 'second_rows', 'note'];
// Team decision 2026-10-27 (spec section 11): H1-H4 are reported with and without these listings.
const VARIANT_IN_TITLE = new Set(['BEAU-005_pchome', 'BEAU-006_momo', 'BEAU-011_momo', 'FOOD-002_pchome',
  'FOOD-003_pchome', 'FOOD-009_pchome', 'FOOD-026_momo', 'FOOD-026_pchome', 'HOME-016_momo', 'HOME-016_pchome']);

const key = t => t.product_id + '_' + t.platform;
const rawFile = (t, verify = false) => path.join(RAW, key(t) + (verify ? '_verify' : '') + '.json.gz');
const readRaw = file => JSON.parse(zlib.gunzipSync(fs.readFileSync(file)).toString('utf8'));
const atomic = (file, data) => {fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file + '.tmp', data); fs.renameSync(file + '.tmp', file);};
const quote = v => /[",\r\n]/.test(String(v)) ? '"' + String(v).replace(/"/g, '""') + '"' : String(v);
const writeCSV = (file, columns, rows) => atomic(file, columns.join(',') + '\n' +
  rows.map(r => columns.map(col => quote(r[col] ?? 'NA')).join(',')).join('\n') + (rows.length ? '\n' : ''));

function targets(root = ROOT) {
  const products = c.parseCSV(fs.readFileSync(path.join(root, 'products', 'products.csv'), 'utf8'));
  const out = [];
  for (const p of products) for (const platform of Object.keys(SHOPS)) {
    if (!p['biggo_url_' + platform]) continue;
    const id = c.itemID(platform, p[platform + '_url']);
    if (!id) throw Error('Missing platform ID: ' + p.product_id + ' ' + platform);
    out.push({product_id: p.product_id, platform, platform_item_id: id, history_id: SHOPS[platform] + '-' + id,
      biggo_url: p['biggo_url_' + platform]});
  }
  if (new Set(out.map(key)).size !== out.length) throw Error('Duplicate product/platform in the product table');
  return out;
}
// Coupang is excluded from the analysis (team decision 2026-10-27), so 2026 collects momo and PChome only.
const collected = list => list.filter(t => t.platform !== 'coupang');

// Tracking coverage for 2026 (spec section 11). Collected on Nov 26, most series have no BigGo point
// after Nov 25 yet, so a series that stops earlier is also covered when our own scrapes confirm its
// price: every successful 15:07 scrape after BigGo's last point shows that point's price as
// lowest_shown_price. The interval starts Sep 1 when BigGo recorded a point inside the window, else
// on the first confirming scrape (BigGo was silent for the whole window, so only scraped days count).
function scrapeCoverage(t, last, scrapes) {
  const after = scrapes.filter(r => r.product_id === t.product_id && r.platform === t.platform && r.slot === '15:07' &&
    r.date <= '2026-11-25' && r.run_started_at.slice(0, 16) > c.tw(last.x));
  if (!after.length || after.some(r => Number(r.lowest_shown_price) !== last.y)) return null;
  const dates = after.map(r => r.date).sort();
  return {coverage_start: last.x >= START ? '2026-09-01' : dates[0], coverage_end: dates.at(-1),
    note: 'BigGo series ends ' + c.tw(last.x) + ' at ' + last.y + '; our 15:07 lowest_shown_price was ' + last.y +
      ' on all ' + after.length + ' scraped days ' + dates[0] + ' to ' + dates.at(-1)};
}
const readScrapes = (root = ROOT) => c.parseCSV(fs.readFileSync(path.join(root, 'data', 'scrapes.csv'), 'utf8'));

function extract(t, record, scrapes = []) {
  const b = record.data;
  // For a listing it no longer tracks, BigGo answers 200 with {"result":true} and nothing else.
  // On 2026-11-26 all 23 such listings were ones our scrapers had stopped reading (taken off sale).
  if (record.status === 200 && b && b.result === true && Object.keys(b).length === 1) {
    const seen = scrapes.filter(r => r.product_id === t.product_id && r.platform === t.platform).map(r => r.date).sort();
    return {rows: [], points: [], baseline: 0, continues: false, coverage: null, noHistory: true, first: 'NA', last: 'NA',
      title: 'NA', current_price: 'NA', note: 'BigGo returned no price history on ' + c.tw(Date.parse(record.collected_at), true) +
        ' (direct request by history_id answered {"result":true} only); ' + (seen.length
        ? 'our scrapers last read the page on ' + seen.at(-1) + ' and failed on every later run, so it was most likely taken off sale'
        : 'our scrapers never read the page successfully')};
  }
  if (record.status !== 200 || !b || b.result !== true || !Array.isArray(b.price_history)) throw Error('No successful history (HTTP ' + record.status + ')');
  if (b.history_id !== t.history_id || b.oid !== t.platform_item_id || b.nindex !== SHOPS[t.platform]) throw Error('Response identity mismatch');
  if (c.itemID(t.platform, b.purl, true) !== t.platform_item_id) throw Error('Response product URL mismatch');
  if (b.currency !== 'TWD') throw Error('Unexpected currency');
  const collectedAt = Date.parse(record.collected_at);
  const points = b.price_history.map(p => {
    if (!Number.isSafeInteger(p.x) || p.x < Date.parse('2000-01-01') || p.x > collectedAt + 86400000 || !Number.isSafeInteger(p.y) || p.y < 0) throw Error('Invalid point');
    return {x: p.x, y: p.y};
  }).sort((a, z) => a.x - z.x);
  const changes = points.filter((p, i) => i === 0 || p.y !== points[i - 1].y);
  const before = changes.filter(p => p.x < START).slice(-1);
  const selected = [...before, ...changes.filter(p => p.x >= START && p.x < END)];
  const last = points.at(-1);
  const continues = !!last && last.x >= END;
  // A series whose last point is at or after the last daily slot (Nov 25, 15:07) already prices every day.
  const stopsEarly = !!last && last.x < LAST_SLOT;
  const coverage = continues
    ? {coverage_start: '2026-09-01', coverage_end: '2026-11-25', note: 'BigGo series continues to ' + c.tw(last.x)}
    : stopsEarly ? scrapeCoverage(t, last, scrapes) : null;
  const notes = [];
  if (VARIANT_IN_TITLE.has(key(t))) notes.push('Variant in BigGo title (team decision 2026-10-27): report H1-H4 with and without this listing');
  if (!before.length) notes.push('No historical baseline before 2026-09-01; first observed ' + (points[0] ? c.tw(points[0].x) : 'NA'));
  // BigGo's 2-year series opens with a point at the window edge (request time minus 730 days), so
  // when that point is the baseline its time is the edge, not a real change.
  const edgeBaseline = before.length === 1 && before[0].x === points[0].x;
  if (edgeBaseline) notes.push('Baseline is the first point of BigGo\'s 2-year window; its time is the window edge, the real change time is earlier and unknown');
  if (stopsEarly) notes.push('Tracking last observed ' + c.tw(last.x) + (coverage
    ? '; carried ' + coverage.coverage_start + ' to ' + coverage.coverage_end + ' because our scrapes confirm the price (history_coverage.csv)'
    : '; do not carry price through 2026-11-25 without evidence'));
  const perMinute = new Map();
  for (const p of selected) perMinute.set(c.tw(p.x), (perMinute.get(c.tw(p.x)) || 0) + 1);
  const rows = selected.map(p => ({product_id: t.product_id, platform: t.platform, biggo_url: t.biggo_url,
    changed_at: c.tw(p.x), price: p.y, entered_by: ENTERED_BY, entered_on: c.tw(collectedAt, true),
    note: [...notes, ...(perMinute.get(c.tw(p.x)) > 1 ? ['Distinct source change UTC milliseconds=' + p.x] : [])].join(' | ') || 'NA'}));
  return {rows, points, baseline: before.length, edgeBaseline, continues, coverage, first: points[0] ? c.tw(points[0].x) : 'NA',
    last: last ? c.tw(last.x) : 'NA', title: b.title, current_price: b.current_price ?? 'NA', note: notes.join(' | ') || 'NA'};
}

function importBundle(file) {
  const bundle = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (bundle.biggo_bundle_version !== 1 || bundle.year !== 2026 || !Array.isArray(bundle.records)) throw Error('Not a 2026 BigGo bundle');
  const byId = new Map(targets().map(t => [t.history_id, t]));
  fs.mkdirSync(RAW, {recursive: true});
  const log = path.join(RAW, 'requests.jsonl');
  const logged = new Set(fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l).sent_at + JSON.parse(l).history_id) : []);
  let saved = 0, skipped = 0;
  for (const r of bundle.records) {
    const t = byId.get(r.history_id);
    if (!t) throw Error('Unknown history_id in bundle: ' + r.history_id);
    if (!logged.has(r.sent_at + r.history_id)) fs.appendFileSync(log, JSON.stringify({kind: r.verify ? 'verify' : 'history', history_id: r.history_id, sent_at: r.sent_at, status: r.status}) + '\n');
    if (r.status !== 200) {skipped++; continue;}
    extract(t, r); // refuse a malformed or mismatched response before saving it
    const out = rawFile(t, !!r.verify);
    if (fs.existsSync(out) && readRaw(out).sent_at !== r.sent_at) throw Error('Refusing to overwrite saved evidence: ' + path.basename(out));
    atomic(out, zlib.gzipSync(JSON.stringify(r)));
    saved++;
  }
  return {saved, skipped_non_200: skipped};
}

function rebuild() {
  const list = targets();
  const scrapes = readScrapes();
  const rows = [], status = [], coverage = [], verification = [];
  for (const t of list) {
    const s = {product_id: t.product_id, platform: t.platform, history_id: t.history_id, status: 'not_collected', rows: 0, baseline: 0};
    if (t.platform === 'coupang') s.note = 'Coupang is excluded from the analysis (team decision 2026-10-27); 2026 history not collected';
    else if (!fs.existsSync(rawFile(t))) s.note = 'No saved response yet';
    else {
      try {
        const d = extract(t, readRaw(rawFile(t)), scrapes);
        rows.push(...d.rows);
        Object.assign(s, {status: d.noHistory ? 'no_history' : d.points.length ? 'retrieved' : 'empty', rows: d.rows.length, baseline: d.baseline,
          first_point_tw: d.first, last_point_tw: d.last, current_price: d.current_price, title: d.title, note: d.note});
        if (d.coverage) coverage.push({product_id: t.product_id, platform: t.platform, ...d.coverage});
        if (fs.existsSync(rawFile(t, true))) {
          const v = extract(t, readRaw(rawFile(t, true)));
          // A window-edge baseline moves with the request time, so it is compared by price only.
          const pairs = x => x.rows.map((r, i) => (i === 0 && x.edgeBaseline ? 'window edge' : r.changed_at) + '=' + r.price);
          const a = pairs(d), b = pairs(v);
          const same = a.length === b.length && a.every((x, i) => x === b[i]);
          verification.push({product_id: t.product_id, platform: t.platform, method: 'second history request, same session',
            result: same ? 'match' : 'discrepancy', first_rows: a.length, second_rows: b.length,
            note: same ? 'NA' : 'Only in first: ' + a.filter(x => !b.includes(x)).join(' ') + '; only in second: ' + b.filter(x => !a.includes(x)).join(' ')});
        }
      } catch (e) {Object.assign(s, {status: 'failed', note: e.message});}
    }
    status.push(s);
  }
  // 2025 coverage rows stay exactly as they are; only the 2026 rows are regenerated.
  const kept = c.parseCSV(fs.readFileSync(COVERAGE, 'utf8')).filter(r => !r.coverage_start.startsWith('2026-'));
  writeCSV(PRICES, c.HEADER, rows);
  writeCSV(STATUS, STATUS_COLUMNS, status);
  writeCSV(VERIFY, VERIFY_COLUMNS, verification);
  writeCSV(COVERAGE, COVERAGE_COLUMNS, [...kept, ...coverage]);
  const n = st => status.filter(r => r.status === st).length;
  return {targets: collected(list).length, retrieved: n('retrieved'), no_history: n('no_history'), empty: n('empty'), failed: n('failed'),
    missing: status.filter(r => r.platform !== 'coupang' && r.status === 'not_collected').length,
    with_2026_rows: status.filter(r => r.rows > 0).length, rows: rows.length, coverage_rows: coverage.length,
    coverage_by_biggo_point: coverage.filter(r => r.note.startsWith('BigGo series continues')).length,
    verified: verification.length, discrepancies: verification.filter(r => r.result !== 'match').length};
}

if (require.main === module) {
  const [mode, arg] = process.argv.slice(2);
  try {
    if (mode === 'targets') console.log(JSON.stringify(collected(targets()).map(t => [t.product_id, t.platform, t.history_id])));
    else if (mode === 'import') console.log(JSON.stringify(importBundle(arg)));
    else if (mode === 'rebuild') console.log(JSON.stringify(rebuild()));
    else throw Error('Usage: collect_2026.cjs targets | import <bundle.json> | rebuild');
  } catch (e) {console.error(e.message); process.exitCode = 1;}
}
module.exports = {targets, collected, extract, scrapeCoverage, importBundle, rebuild, START, END, VARIANT_IN_TITLE};
