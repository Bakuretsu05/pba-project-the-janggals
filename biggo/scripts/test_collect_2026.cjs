const test = require('node:test');
const assert = require('node:assert/strict');
const c = require('./collect_2026.cjs');

const t = {product_id: 'TEST', platform: 'momo', platform_item_id: '123', history_id: 'tw_pec_momoshop-123', biggo_url: 'https://biggo.com.tw/s/test'};
const point = (time, price) => ({x: Date.parse(time), y: price});
const record = (points, data = {}) => ({status: 200, collected_at: '2026-11-26T12:00:00Z', data: {result: true, history_id: t.history_id,
  oid: '123', nindex: 'tw_pec_momoshop', purl: 'https://www.momoshop.com.tw/product/123', currency: 'TWD', title: '測試商品',
  current_price: 90, price_history: points, ...data}});

test('keeps the last change before Sep 1, 2026 and every change through Nov 25', () => {
  const r = c.extract(t, record([
    point('2025-10-01T00:00:00+08:00', 100),
    point('2026-08-20T00:00:00+08:00', 90),
    point('2026-08-30T00:00:00+08:00', 90),   // repeat of the same price: not a change
    point('2026-09-01T00:00:00+08:00', 95),
    point('2026-11-11T00:00:00+08:00', 80),
    point('2026-11-25T23:59:59+08:00', 90),
    point('2026-11-26T10:00:00+08:00', 99)    // after the window: evidence of tracking only
  ]));
  assert.deepEqual(r.rows.map(x => [x.changed_at, x.price]), [['2026-08-20 00:00', 90], ['2026-09-01 00:00', 95],
    ['2026-11-11 00:00', 80], ['2026-11-25 23:59', 90]]);
  assert.equal(r.continues, true);
  assert.equal(r.rows[0].entered_by, 'Marvin');
  assert.equal(r.rows[0].entered_on, '2026-11-26');
  assert.equal(r.rows[0].note, 'NA');
});

test('a series that stops before Nov 26 is flagged and gets no coverage', () => {
  const r = c.extract(t, record([point('2026-09-10T00:00:00+08:00', 95), point('2026-10-01T00:00:00+08:00', 90)]));
  assert.equal(r.continues, false);
  assert.match(r.note, /No historical baseline before 2026-09-01/);
  assert.match(r.note, /Tracking last observed 2026-10-01 00:00; do not carry/);
});

test('our scrapes can confirm a series that stops before Nov 26', () => {
  const scrape = (date, price, time = '15:07:30', slot = '15:07') => ({product_id: 'TEST', platform: 'momo', date, slot,
    run_started_at: date + ' ' + time, lowest_shown_price: String(price)});
  const points = [point('2026-08-01T00:00:00+08:00', 95), point('2026-10-20T12:00:00+08:00', 90)];
  const scrapes = [scrape('2026-10-19', 95), scrape('2026-10-20', 999, '15:07:30', 'off-schedule'),
    scrape('2026-10-20', 90), scrape('2026-11-25', 90), scrape('2026-11-26', 50)];
  const r = c.extract(t, record(points), scrapes);
  assert.deepEqual([r.coverage.coverage_start, r.coverage.coverage_end], ['2026-09-01', '2026-11-25']);
  assert.match(r.coverage.note, /on all 2 scraped days 2026-10-20 to 2026-11-25/);
  assert.match(r.note, /carried 2026-09-01 to 2026-11-25 because our scrapes confirm/);
  // one different scraped price after the last point: no coverage
  assert.equal(c.extract(t, record(points), [...scrapes, scrape('2026-11-11', 85)]).coverage, null);
  // NA is not a confirmation
  assert.equal(c.extract(t, record(points), [...scrapes, scrape('2026-11-11', 'NA')]).coverage, null);
  // BigGo silent for the whole window: only the scraped days are covered
  const silent = c.extract(t, record([point('2026-08-01T00:00:00+08:00', 95)]), [scrape('2026-10-19', 95), scrape('2026-11-25', 95)]);
  assert.deepEqual([silent.coverage.coverage_start, silent.coverage.coverage_end], ['2026-10-19', '2026-11-25']);
});

test('variant-in-title listings carry the team flag', () => {
  const v = {...t, product_id: 'BEAU-006'};
  assert.match(c.extract(v, record([point('2026-08-01T00:00:00+08:00', 1)])).note, /Variant in BigGo title/);
});

test('refuses a response for another listing or a failed request', () => {
  assert.throws(() => c.extract(t, record([], {oid: '999'})), /identity/);
  assert.throws(() => c.extract(t, {...record([]), status: 429}), /No successful history/);
});

test('targets are the 300 momo and PChome listings', () => {
  const list = c.collected(c.targets());
  assert.equal(list.filter(x => x.platform === 'momo').length, 150);
  assert.equal(list.filter(x => x.platform === 'pchome').length, 150);
});
