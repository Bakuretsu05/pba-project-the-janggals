const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const zlib=require('node:zlib');
const {spawnSync}=require('node:child_process');
const c=require('./collect_2025.cjs');
const t={product_id:'TEST',platform:'momo',platform_item_id:'123',history_id:'tw_pec_momoshop-123',biggo_url:'https://biggo.com.tw/s/test',coverage:{class:'OK',note:''}};
const point=(time,price)=>({x:Date.parse(time),y:price});
function record(points){return {status:200,collected_at:'2026-10-25T12:00:00Z',data:{result:true,history_id:t.history_id,oid:'123',nindex:'tw_pec_momoshop',purl:'https://www.momoshop.com.tw/product/123',currency:'TWD',title:'測試商品',price_history:points}};}
test('Taiwan date rolls over from UTC and keeps minutes',()=>{
  assert.equal(c.tw(Date.parse('2025-09-30T16:04:59Z')),'2025-10-01 00:04');
});
test('only consecutive equal prices collapse; baseline is last real change',()=>{
  const r=c.extract(t,record([
    point('2025-09-01T00:00:00+08:00',100),
    point('2025-09-20T00:00:00+08:00',90),
    point('2025-09-30T00:00:00+08:00',90),
    point('2025-10-01T00:00:00+08:00',100),
    point('2025-10-01T01:00:00+08:00',90),
    point('2025-10-01T02:00:00+08:00',100),
    point('2025-11-25T23:59:59+08:00',110),
    point('2025-11-26T00:00:00+08:00',120),
    point('2026-10-01T00:00:00+08:00',130)
  ]));
  assert.deepEqual(r.rows.map(x=>x.price),[90,100,90,100,110]);
  assert.equal(r.rows[0].changed_at,'2025-09-20 00:00');
  assert.ok(r.rows.every(x=>x.entered_on==='2026-10-25'&&x.entered_by==='Albert'));
});
test('same-minute reversals retained with source timestamp in note',()=>{
  const r=c.extract(t,record([point('2025-09-01T00:00Z',100),point('2025-10-01T00:00:01Z',90),point('2025-10-01T00:00:11Z',100),point('2025-10-01T00:00:21Z',90)]));
  assert.equal(r.rows.length,4);
  assert.notEqual(r.rows[1].note,r.rows[3].note);
});
test('SHORT retains observed changes and flags missing baseline',()=>{
  const r=c.extract({...t,coverage:{class:'SHORT',note:'Missing baseline'}},record([point('2025-10-19T00:00Z',100)]));
  assert.equal(r.baseline,0);assert.equal(r.rows.length,1);assert.match(r.rows[0].note,/No historical baseline/);
  assert.match(r.rows[0].note,/do not carry price/);
});
test('MISMATCH records retained with explicit warning',()=>{
  const r=c.extract({...t,coverage:{class:'MISMATCH',note:'wrong colour'}},record([point('2025-09-01T00:00Z',100)]));
  assert.match(r.rows[0].note,/MISMATCH.*wrong colour/);
});
test('2026-only history produces no price rows',()=>assert.equal(c.extract(t,record([point('2026-10-14T00:00Z',100)])).rows.length,0));
test('empty history creates no fabricated records',()=>assert.equal(c.extract(t,record([])).rows.length,0));
test('invalid numeric values and identities are rejected',()=>{
  for(const price of [null,-1,1.5,'100',NaN])assert.throws(()=>c.extract(t,record([point('2025-10-01T00:00Z',price)])));
  const r=record([]);r.data.oid='456';assert.throws(()=>c.extract(t,r),/identity/);
});
test('IDs use product URLs, Coupang product ID rather than itemId',()=>{
  assert.equal(c.itemID('momo','https://www.momoshop.com.tw/goods/GoodsDetail.jsp?i_code=123&utm_source=x'),'123');
  assert.equal(c.itemID('pchome','https://24h.pchome.com.tw/prod/DYAJD2-A900GAFRM?x=1'),'DYAJD2-A900GAFRM');
  assert.equal(c.itemID('coupang','https://www.tw.coupang.com/products/123?itemId=456'),'123');
  assert.throws(()=>c.itemID('momo','https://example.com/product/123'));
});
test('CSV reader preserves Chinese and quoted commas/newlines',()=>{
  assert.deepEqual(c.parseCSV('\uFEFFid,note\r\n1,"中文,\n""引號"""\r\n'),[{id:'1',note:'中文,\n"引號"'}]);
});
test('335 identities agree with coverage; stratified repeat sample has 34',()=>{
  const ts=c.targets();assert.equal(ts.length,335);
  const s=c.auditSample(ts);assert.equal(s.length,34);assert.equal(new Set(s.map(x=>x.history_id)).size,34);
  assert.equal(s.filter(t=>t.coverage.class==='SHORT').length,8);
  assert.equal(s.filter(t=>t.coverage.class==='MISMATCH').length,1);
  assert.equal(s.filter(t=>t.coverage.note.includes('cannot tell unchanged price from stopped tracking')).length,13);
});

function checkout(t, populated=false) {
  const prefix=path.join(os.tmpdir(),'biggo-2025-test-');
  const root=fs.mkdtempSync(prefix);
  t.after(()=>{assert.ok(path.resolve(root).startsWith(path.resolve(prefix)));fs.rmSync(root,{recursive:true,force:true});});
  fs.mkdirSync(path.join(root,'biggo'));fs.mkdirSync(path.join(root,'products'));
  for(const name of ['collect_2025.cjs','coverage_check_2026-10-22.csv',...(populated?['price_changes.csv','collection_status_2025.csv','verification_2025.csv']:[])])fs.copyFileSync(path.join(__dirname,name),path.join(root,'biggo',name));
  fs.copyFileSync(path.join(__dirname,'../products/products.csv'),path.join(root,'products/products.csv'));
  if(!populated)fs.writeFileSync(path.join(root,'biggo/price_changes.csv'),c.HEADER.join(',')+'\n');
  return root;
}
const runRebuild=root=>spawnSync(process.execPath,[path.join(root,'biggo/collect_2025.cjs'),'rebuild'],{encoding:'utf8'});
const snapshot=root=>['price_changes.csv','collection_status_2025.csv'].map(f=>fs.readFileSync(path.join(root,'biggo',f)));
function refusedWithoutChanges(root, before) {
  const result=runRebuild(root);
  assert.equal(result.status,1,result.stdout+result.stderr);
  assert.match(result.stderr,/Refusing rebuild/);
  assert.deepEqual(snapshot(root),before,'CSV and status must remain byte-for-byte unchanged');
}
function rawFixture(t) {
  const root=checkout(t),ts=c.targets().slice(0,2),raw=path.join(root,'biggo/raw/2025');
  fs.mkdirSync(raw,{recursive:true});
  const save=(target,points)=>{
    const r=record(points);Object.assign(r.data,{history_id:target.history_id,oid:target.platform_item_id,nindex:target.history_id.slice(0,-target.platform_item_id.length-1),purl:target[target.platform+'_url']});
    const file=path.join(raw,target.product_id+'_'+target.platform+'.json.gz');
    fs.writeFileSync(file,zlib.gzipSync(JSON.stringify(r)));return file;
  };
  const first=save(ts[0],[point('2025-09-01T00:00Z',100),point('2025-10-02T00:00Z',110)]);
  const zero=save(ts[1],[point('2026-10-14T00:00Z',100)]);
  const result=runRebuild(root);assert.equal(result.status,0,result.stderr);
  return {root,first,zero,save,ts};
}
test('fresh checkout with all 1397 rows and no raw refuses rebuild without modifying outputs',t=>{
  const root=checkout(t,true),before=snapshot(root);
  assert.equal(c.parseCSV(before[0].toString()).length,1397);
  refusedWithoutChanges(root,before);
});
test('an empty raw directory cannot erase existing records',t=>{
  const root=checkout(t,true),before=snapshot(root);
  fs.mkdirSync(path.join(root,'biggo/raw/2025'),{recursive:true});
  refusedWithoutChanges(root,before);
});
test('one missing raw response cannot erase its existing records',t=>{
  const {root,first}=rawFixture(t),before=snapshot(root);
  fs.unlinkSync(first);refusedWithoutChanges(root,before);
});
test('missing evidence for a zero-row retrieved listing preserves status',t=>{
  const {root,zero}=rawFixture(t),before=snapshot(root);
  fs.unlinkSync(zero);refusedWithoutChanges(root,before);
});
test('corrupt evidence cannot erase existing records',t=>{
  const {root,first}=rawFixture(t),before=snapshot(root);
  fs.writeFileSync(first,'not gzip');refusedWithoutChanges(root,before);
});
test('a valid but truncated history cannot replace existing records',t=>{
  const {root,save,ts}=rawFixture(t),before=snapshot(root);
  save(ts[0],[point('2025-09-01T00:00Z',100)]);refusedWithoutChanges(root,before);
});
test('complete fixture evidence rebuilds without changing existing outputs',t=>{
  const {root}=rawFixture(t),before=snapshot(root);
  const result=runRebuild(root);assert.equal(result.status,0,result.stderr);
  assert.deepEqual(snapshot(root),before);
});
