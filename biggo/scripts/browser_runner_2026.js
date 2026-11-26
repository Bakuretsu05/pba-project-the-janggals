// Browser side of the 2026 BigGo collection (collect_2026.cjs has the rest).
// Run in a biggo.com.tw tab that is signed in to a team member's BigGo account (spec section 3).
// It defines window.bigGo2026:
//   run(targets, {verify})  fetch each [product_id, platform, history_id] not yet saved, one request
//                           every 5.2 s, and stop at the first response that is not a successful history
//   state                   progress: running, done, stopReason, lastStatus
//   counts()                saved responses by kind
//   exportBundle()          download everything saved as biggo_2026_bundle.json, for
//                           `node biggo/scripts/collect_2026.cjs import <file>`
// Responses are kept in this origin's IndexedDB, so a page reload (needed when the
// session token expires after about 35 minutes) loses nothing: paste this again and rerun.
// No cookie, token or password is read or saved; the request is the page's own history call.
(() => {
  const DB = 'biggo2026', STORE = 'records', PACE = 5200;
  const open = () => new Promise((resolve, reject) => {
    const r = indexedDB.open(DB, 1);
    r.onupgradeneeded = () => r.result.createObjectStore(STORE, {keyPath: 'key'});
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
  const tx = async (mode, fn) => {
    const db = await open();
    return new Promise((resolve, reject) => {
      const t = db.transaction(STORE, mode);
      const req = fn(t.objectStore(STORE));
      t.oncomplete = () => {db.close(); resolve(req.result);};
      t.onerror = () => {db.close(); reject(t.error);};
    });
  };
  const put = rec => tx('readwrite', s => s.put(rec));
  const all = () => tx('readonly', s => s.getAll());
  const state = {running: false, stop: false, stopReason: null, done: 0, last: 0, lastStatus: null};

  async function run(targets, {verify = false} = {}) {
    if (state.running) return 'already running';
    Object.assign(state, {running: true, stop: false, stopReason: null, done: 0});
    try {
      const have = new Set((await all()).map(r => r.key));
      for (const [product_id, platform, history_id] of targets) {
        const key = product_id + '_' + platform + (verify ? '_verify' : '');
        if (have.has(key)) continue;
        if (state.stop) {state.stopReason = 'stopped by hand'; break;}
        const wait = PACE - (Date.now() - state.last);
        if (wait > 0) await new Promise(r => setTimeout(r, wait));
        state.last = Date.now();
        const sent_at = new Date(state.last).toISOString();
        let status = 0, data;
        try {
          const r = await fetch('/api/v1/spa/product/history', {method: 'POST', headers: {'content-type': 'application/json'},
            body: JSON.stringify({history_id, days: 730}), signal: AbortSignal.timeout(30000)});
          status = r.status;
          const text = await r.text();
          try {data = JSON.parse(text);} catch {data = {error: 'non-JSON response', body: text.slice(0, 500)};}
        } catch (e) {data = {error: String(e)};}
        state.lastStatus = status;
        const rec = {key, product_id, platform, history_id, verify, sent_at, collected_at: new Date().toISOString(), signed_in: true, status, data};
        if (status !== 200 || !data || data.result !== true) {
          await put({...rec, key: 'failed_' + sent_at});
          state.stopReason = 'HTTP ' + status + ' at ' + history_id + ': ' + JSON.stringify(data).slice(0, 200);
          break;
        }
        await put(rec);
        state.done++;
      }
    } finally {state.running = false;}
    return state.stopReason || 'finished';
  }

  async function counts() {
    const recs = await all();
    const out = {history: 0, verify: 0, failed: 0};
    for (const r of recs) out[r.key.startsWith('failed_') ? 'failed' : r.verify ? 'verify' : 'history']++;
    return out;
  }

  async function exportBundle() {
    const records = (await all()).map(({key, ...r}) => r);
    const blob = new Blob([JSON.stringify({biggo_bundle_version: 1, year: 2026, records})], {type: 'application/json'});
    const a = Object.assign(document.createElement('a'), {href: URL.createObjectURL(blob), download: 'biggo_2026_bundle.json'});
    document.body.appendChild(a); a.click(); a.remove();
    return {records: records.length, bytes: blob.size};
  }

  window.bigGo2026 = {run, state, counts, exportBundle};
  return 'bigGo2026 ready';
})();
