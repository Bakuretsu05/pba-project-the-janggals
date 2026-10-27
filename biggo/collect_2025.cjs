#!/usr/bin/env node
// Run from the repository root. Requires Playwright and installed Google Chrome.
// No login, saved browser profile, session-token export, or 2026 dataset output.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const ROOT = path.resolve(__dirname, '..');
const DIR = __dirname;
const RAW = path.join(DIR, 'raw', '2025');
const BLOCKER = path.join(DIR, 'access_blocker_2025.json');
const HEADER = ['product_id','platform','biggo_url','changed_at','price','entered_by','entered_on','note'];
const SHOPS = {momo:'tw_pec_momoshop',pchome:'tw_ec_pchome24h',coupang:'tw_pec_coupang'};
const START = Date.parse('2025-09-01T00:00:00+08:00');
const PRIOR_START = Date.parse('2025-10-01T00:00:00+08:00');
const END = Date.parse('2025-11-26T00:00:00+08:00');
const PACE = 5200;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const tw = (ms, dateOnly=false) => new Date(ms+8*3600000).toISOString().slice(0,dateOnly?10:16).replace('T',' ');

// Small RFC 4180 reader; preserves Chinese, commas, quoted newlines, and empty cells.
function parseCSV(text) {
  const rows=[]; let row=[], field='', quoted=false;
  text=text.replace(/^\uFEFF/,'');
  for(let i=0;i<text.length;i++) {
    const c=text[i];
    if(c==='"') { if(quoted && text[i+1]==='"') {field+='"'; i++;} else quoted=!quoted; }
    else if(c===',' && !quoted) {row.push(field);field='';}
    else if((c==='\n'||c==='\r') && !quoted) {
      if(c==='\r'&&text[i+1]==='\n') i++;
      row.push(field); if(row.some(Boolean)) rows.push(row); row=[];field='';
    } else field+=c;
  }
  if(quoted) throw Error('Unterminated CSV quote');
  if(field||row.length) {row.push(field);rows.push(row);}
  const columns=rows.shift();
  return rows.map(r=>{if(r.length!==columns.length)throw Error('Invalid CSV width');return Object.fromEntries(columns.map((c,i)=>[c,r[i]]));});
}
const readCSV = file => parseCSV(fs.readFileSync(file,'utf8'));
const quote = value => /[",\r\n]/.test(String(value)) ? '"'+String(value).replace(/"/g,'""')+'"' : String(value);
function atomic(file, data) {fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file+'.tmp',data);fs.renameSync(file+'.tmp',file);}
function writeCSV(file, columns, rows) {atomic(file, columns.join(',')+'\n'+rows.map(r=>columns.map(c=>quote(r[c]??'NA')).join(',')).join('\n')+(rows.length?'\n':''));}
function itemID(platform, link, responseURL=false) {
  const u=new URL(link);
  if(platform==='momo' && /(^|\.)momoshop\.com\.tw$/.test(u.hostname)) return u.searchParams.get('i_code')||u.pathname.match(/^\/product\/(\d+)/)?.[1];
  if(platform==='pchome' && u.hostname==='24h.pchome.com.tw') return u.pathname.match(/^\/prod\/([A-Z0-9]{6}-[A-Z0-9]{9}(?:-\d{3})?)(?:\/|$)/i)?.[1];
  if(platform==='coupang' && /(^|\.)coupang\.com$/.test(u.hostname)) return u.pathname.match(/^\/products\/(\d+)/)?.[1];
  if(responseURL && platform==='coupang' && u.hostname==='coupang.onelink.me') {
    const id=u.searchParams.get('pageKey');
    const deep=new URL(u.searchParams.get('deep_link_value'));
    if(/^\d+$/.test(id)&&deep.searchParams.get('pId')===id)return id;
  }
  throw Error('Invalid platform URL: '+platform);
}
function targets() {
  const products=readCSV(path.join(ROOT,'products/products.csv'));
  const coverage=readCSV(path.join(DIR,'coverage_check_2026-10-22.csv'));
  const seen=new Set(); const out=[];
  for(const p of products) {
    if(seen.has(p.product_id))throw Error('Duplicate product ID');seen.add(p.product_id);
    for(const platform of Object.keys(SHOPS)) {
      if(!p['biggo_url_'+platform])continue;
      const id=itemID(platform,p[platform+'_url']);
      if(!id)throw Error('Missing platform ID: '+p.product_id+' '+platform);
      const history_id=SHOPS[platform]+'-'+id;
      const old=coverage.find(r=>r.product_id===p.product_id&&r.platform===platform);
      if(!old||old.history_id_used!==history_id)throw Error('Coverage ID differs from product table');
      out.push({...p,platform,history_id,platform_item_id:id,biggo_url:p['biggo_url_'+platform],coverage:old});
    }
  }
  for(const [platform,n] of Object.entries({momo:150,pchome:150,coupang:35}))
    if(out.filter(t=>t.platform===platform).length!==n)throw Error('Unexpected target count: '+platform);
  return out;
}
const key=t=>t.product_id+'_'+t.platform;
const rawFile=(t,verify=false)=>path.join(RAW,key(t)+(verify?'_verify':'')+'.json.gz');
const readRaw=file=>JSON.parse(zlib.gunzipSync(fs.readFileSync(file)).toString('utf8'));
function visibleData(t,record) {
  if(record.history_id!==t.history_id||record.product_id!==t.product_id||record.platform!==t.platform||record.range!=='最近2年')throw Error('Visible history identity or range mismatch');
  const link=new URL(record.listing_url,'https://biggo.com.tw');
  if(link.hostname!=='biggo.com.tw'||link.searchParams.get('id')!==t.platform_item_id||link.searchParams.get('i')!==SHOPS[t.platform])throw Error('Visible listing link mismatch');
  const source=new URL(record.source_url);
  if(source.hostname!=='biggo.com.tw'||!source.searchParams.getAll('c[]').includes(SHOPS[t.platform]))throw Error('Visible search platform mismatch');
  const purl=link.searchParams.get('purl');
  if(itemID(t.platform,purl,true)!==t.platform_item_id)throw Error('Visible product URL mismatch');
  const points=[];
  for(const line of record.table.split('\n')) {
    if(line.startsWith('現在\t'))continue;
    const match=line.match(/^(\d{4}-\d\d-\d\d \d\d:\d\d)\t\$([\d,]+)\t/);
    if(!match)throw Error('Invalid visible history row');
    const x=Date.parse(match[1].replace(' ','T')+':00+08:00');
    if(!Number.isSafeInteger(x)||tw(x)!==match[1])throw Error('Invalid visible calendar timestamp');
    points.push({x,y:Number(match[2].replace(/,/g,''))});
  }
  if(!points.length||!record.title)throw Error('Visible history is empty');
  return {result:true,history_id:t.history_id,oid:t.platform_item_id,nindex:SHOPS[t.platform],purl,currency:'TWD',title:record.title,price_history:points.reverse()};
}
function extract(t, record, start=START) {
  if(record.source==='biggo_visible_error')throw Error(record.error);
  const visible=record.source==='biggo_visible_table';
  const b=visible?visibleData(t,record):record.data;
  if((!visible&&record.status!==200)||b.result!==true||!Array.isArray(b.price_history)) throw Error('No successful history');
  if(b.history_id!==t.history_id||b.oid!==t.platform_item_id||b.nindex!==SHOPS[t.platform])throw Error('Response identity mismatch');
  if(itemID(t.platform,b.purl,true)!==t.platform_item_id)throw Error('Response product URL mismatch');
  if(b.currency!=='TWD')throw Error('Unexpected currency');
  const points=b.price_history.map(p=>{
    if(!Number.isSafeInteger(p.x)||p.x<Date.parse('2000-01-01')||p.x>Date.parse(record.collected_at)+86400000||!Number.isSafeInteger(p.y)||p.y<0)throw Error('Invalid point');
    return {x:p.x,y:p.y};
  }).sort((a,b)=>a.x-b.x);
  const changes=points.filter((p,i)=>i===0||p.y!==points[i-1].y);
  const before=changes.filter(p=>p.x<start).slice(-1);
  const selected=[...before,...changes.filter(p=>p.x>=start&&p.x<END)];
  const notes=[];
  if(visible)notes.push('Source: signed-in BigGo visible history table; Taiwan time at displayed minute precision');
  if(record.catalog_variant)notes.push('Selected catalog variant: '+record.catalog_variant);
  if(record.quality_warning)notes.push(record.quality_warning);
  if(visible) {
    // Marvin's reference summary still describes Oct 1-Nov 25, not the new window.
    const period=points.filter(p=>p.x>=PRIOR_START&&p.x<END).map(p=>p.y);
    if(period.length!==Number(t.coverage.n_points_2025_10_01_to_11_25)||(period.length&&(Math.min(...period)!==Number(t.coverage.min_price_in_period)||Math.max(...period)!==Number(t.coverage.max_price_in_period))))notes.push('Visible 2025 history differs from prior coverage summary; verify coverage/selected variant');
  }
  if(t.coverage.class!=='OK')notes.push('Coverage '+t.coverage.class+' (2026-10-22): '+t.coverage.note);
  if(!before.length)notes.push('No historical baseline before '+tw(start,true)+'; first observed '+(points[0]?tw(points[0].x):'NA'));
  if(points.length&&points.at(-1).x<END-60000)notes.push('Tracking last observed '+tw(points.at(-1).x)+'; do not carry price through 2025-11-25 without evidence');
  if(before.length===1&&before[0].x===points[0]?.x)notes.push('Baseline is first observed point in available history; earlier change time unknown');
  const minuteCounts=new Map();for(const p of selected)minuteCounts.set(tw(p.x),(minuteCounts.get(tw(p.x))||0)+1);
  const rows=selected.map((p,eventIndex)=>({product_id:t.product_id,platform:t.platform,biggo_url:t.biggo_url,changed_at:tw(p.x),price:p.y,entered_by:'Albert',entered_on:tw(Date.parse(record.collected_at),true),note:[...notes,...(minuteCounts.get(tw(p.x))>1?[visible?'Distinct visible change in table order='+eventIndex:'Distinct source change UTC milliseconds='+p.x]:[])].join(' | ')||'NA'}));
  return {rows,points,changes,baseline:before.length,first:points[0]?tw(points[0].x):'NA',last:points.length?tw(points.at(-1).x):'NA',title:b.title,note:notes.join(' | ')||'NA'};
}
function rebuild(list, extendWindow=false) {
  if(!fs.existsSync(RAW))throw Error('Refusing rebuild: required raw/2025 evidence is unavailable; existing CSV and status files were not changed.');
  const rows=[], coverage=[], priorRows=[];
  const chartFile=path.join(DIR,'chart_checks_2025.csv');
  const chartReviews=fs.existsSync(chartFile)?readCSV(chartFile):[];
  for(const t of list) {
    let c={product_id:t.product_id,platform:t.platform,history_id:t.history_id,prior_class:t.coverage.class,status:'not_attempted',rows:0,baseline:0,title:t.coverage.title,note:t.coverage.note||'NA'};
    if(fs.existsSync(rawFile(t))) {
      try {const record=readRaw(rawFile(t));const d=extract(t,record);rows.push(...d.rows);if(extendWindow)priorRows.push(...extract(t,record,PRIOR_START).rows);c={...c,status:d.points.length?'retrieved':'empty',rows:d.rows.length,baseline:d.baseline,first_point_tw:d.first,last_point_tw:d.last,title:d.title,note:d.note};}
      catch(e){c={...c,status:'failed',note:e.message};}
    } else if(fs.existsSync(path.join(RAW,key(t)+'_attempt1.json.gz'))) {
      const attempt=readRaw(path.join(RAW,key(t)+'_attempt1.json.gz'));
      c={...c,status:attempt.data.require_login?'blocked_login':'failed',note:'HTTP '+attempt.status+'; '+JSON.stringify(attempt.data)};
    }
    const review=chartReviews.find(r=>r.product_id===t.product_id&&r.platform===t.platform&&r.result==='discrepancy');
    if(review)c.note+=' | UNRESOLVED independent chart discrepancy: '+review.note;
    coverage.push(c);
  }
  // Check all prior records before either output is written. Never turn missing,
  // corrupt or truncated evidence into silent data loss (including zero-row series).
  const csv=path.join(DIR,'price_changes.csv');
  if(fs.existsSync(csv)) {
    const header=fs.readFileSync(csv,'utf8').replace(/^\uFEFF/,'').split(/\r?\n/,1)[0];
    if(header!==HEADER.join(','))throw Error('Refusing rebuild: existing CSV header is invalid; no files changed.');
    const fingerprint=r=>JSON.stringify(HEADER.map(c=>String(r[c]??'NA')));
    const available=new Map();
    for(const row of rows) {const k=fingerprint(row);available.set(k,(available.get(k)||0)+1);}
    // Explicit September migration may regenerate window-dependent notes only.
    // Old rows must still match their old-window raw reconstruction exactly, and
    // every non-note field must remain present in the expanded reconstruction.
    const facts=r=>JSON.stringify(HEADER.filter(c=>c!=='note').map(c=>String(r[c]??'NA')));
    const factCounts=new Map(),legacy=new Map();
    for(const row of rows){const k=facts(row);factCounts.set(k,(factCounts.get(k)||0)+1);}
    for(const row of priorRows){const k=fingerprint(row);legacy.set(k,(legacy.get(k)||0)+1);}
    for(const row of readCSV(csv)) {
      const k=fingerprint(row),f=facts(row);
      if(!factCounts.get(f)||(!available.get(k)&&!legacy.get(k)))throw Error('Refusing rebuild: missing, invalid or incomplete raw evidence would remove or change existing records ('+row.product_id+' '+row.platform+'); no files changed.');
      factCounts.set(f,factCounts.get(f)-1);
      if(available.get(k))available.set(k,available.get(k)-1);else legacy.set(k,legacy.get(k)-1);
    }
  }
  const statusFile=path.join(DIR,'collection_status_2025.csv');
  if(fs.existsSync(statusFile))for(const prior of readCSV(statusFile)) {
    if(!['retrieved','empty'].includes(prior.status))continue;
    const current=coverage.find(c=>c.product_id===prior.product_id&&c.platform===prior.platform);
    if(!current||!['retrieved','empty'].includes(current.status))throw Error('Refusing rebuild: raw evidence for previously retrieved listing is unavailable or invalid ('+prior.product_id+' '+prior.platform+'); no files changed.');
  }
  if(!coverage.some(c=>['retrieved','empty'].includes(c.status)))throw Error('Refusing rebuild: no valid raw histories are available; no files changed.');
  writeCSV(path.join(DIR,'price_changes.csv'),HEADER,rows);
  writeCSV(path.join(DIR,'collection_status_2025.csv'),['product_id','platform','history_id','prior_class','status','rows','baseline','first_point_tw','last_point_tw','title','note'],coverage);
  return {target_listings:list.length,retrieved:coverage.filter(c=>c.status==='retrieved').length,with_2025_records:coverage.filter(c=>c.rows>0).length,rows:rows.length};
}
function auditSample(list) {
  // All 8 SHORT, the mismatch, all 13 stopped series, then across classes/platforms.
  const sample=list.filter(t=>t.coverage.class==='SHORT'||t.coverage.class==='MISMATCH'||t.coverage.note.includes('cannot tell unchanged price from stopped tracking'));
  for(const cl of ['UNCERTAIN','OK'])for(const platform of Object.keys(SHOPS)) {
    for(const t of list.filter(t=>t.coverage.class===cl&&t.platform===platform&&!sample.includes(t)).slice(0,2))sample.push(t);
  }
  for(const t of list)if(sample.length<34&&!sample.includes(t))sample.push(t);
  return sample.slice(0,34);
}
function verifySaved(list) {
  const rows=[];
  for(const t of auditSample(list)) {
    if(!fs.existsSync(rawFile(t))||!fs.existsSync(rawFile(t,true)))continue;
    const a=extract(t,readRaw(rawFile(t))),b=extract(t,readRaw(rawFile(t,true)));
    const values=d=>d.rows.map(r=>[r.changed_at,r.price]);
    const same=JSON.stringify(values(a))===JSON.stringify(values(b));
    rows.push({product_id:t.product_id,platform:t.platform,prior_class:t.coverage.class,method:'second signed-out history request',result:same?'match':'DISCREPANCY',first_rows:a.rows.length,second_rows:b.rows.length,note:same?'NA':'Review raw responses before using'});
  }
  writeCSV(path.join(DIR,'verification_2025.csv'),['product_id','platform','prior_class','method','result','first_rows','second_rows','note'],rows);
  return rows;
}
function contact() {
  let value=process.env.SCRAPER_CONTACT;
  const f=path.join(ROOT,'.Renviron');
  if(!value&&fs.existsSync(f))value=fs.readFileSync(f,'utf8').replace(/^\uFEFF/,'').split(/\r?\n/).find(l=>l.startsWith('SCRAPER_CONTACT='))?.slice(16).trim().replace(/^['"]|['"]$/g,'');
  if(!value||!/^\S+@\S+\.\S+$/.test(value)||/[\r\n]/.test(value))throw Error('Set valid SCRAPER_CONTACT in environment or .Renviron (no request sent)');
  return value;
}
async function collect(mode='collect') {
  const list=targets();
  if(mode==='rebuild'){console.log(JSON.stringify(rebuild(list,process.argv.includes('--extend-window'))));verifySaved(list);return;}
  if(fs.existsSync(BLOCKER))throw Error('Historical signed-out login restriction. Spec section 3 now permits signed-in BigGo collection; use the authorized browser session, not this fresh signed-out collector. See biggo/access_blocker_2025.json.');
  // Resolve before browser startup, and keep contact out of saved evidence.
  const userAgent=`PBA-Double11-study (NTHU ISS4066; contact: ${contact()})`;
  let pw;try{pw=require('playwright');}catch(e){if(!process.env.PLAYWRIGHT_MODULE)throw e;pw=require(process.env.PLAYWRIGHT_MODULE);}
  const browser=await pw.chromium.launch({channel:'chrome',headless:!process.argv.includes('--headed')});
  const context=await browser.newContext({userAgent});
  const page=await context.newPage();
  let last=0;
  const pace=async()=>{await sleep(Math.max(0,PACE-(Date.now()-last)));last=Date.now();};
  const log=entry=>fs.appendFileSync(path.join(RAW,'requests.jsonl'),JSON.stringify(entry)+'\n');
  async function home() {
    await pace();log({kind:'home',sent_at:new Date(last).toISOString()});
    await page.goto('https://biggo.com.tw/',{waitUntil:'domcontentloaded',timeout:30000});
    await page.getByRole('button',{name:'登入',exact:true}).waitFor({state:'visible',timeout:30000});
  }
  async function history(t,verify=false) {
    for(let attempt=0;attempt<2;attempt++) {
      await pace(); const sent_at=new Date(last).toISOString();
      let r;
      try {
        r=await page.evaluate(async id=>{
          const response=await fetch('/api/v1/spa/product/history',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({history_id:id,days:730}),signal:AbortSignal.timeout(30000)});
          return {status:response.status,body:await response.text()};
        },t.history_id);
      }catch(e){r={status:0,body:JSON.stringify({error:e.message})};}
      let data;try{data=JSON.parse(r.body);}catch{data={error:'non-JSON response',body:r.body};}
      const record={history_id:t.history_id,sent_at,collected_at:new Date().toISOString(),signed_in:false,status:r.status,data};
      atomic(path.join(RAW,key(t)+(verify?'_verify':'')+'_attempt'+(attempt+1)+'.json.gz'),zlib.gzipSync(JSON.stringify(record)));
      log({kind:verify?'verify':'history',history_id:t.history_id,sent_at,status:r.status,attempt:attempt+1,require_login:data.require_login===true});
      if(data.require_login===true||r.status===403) {
        atomic(BLOCKER,JSON.stringify({product_id:t.product_id,platform:t.platform,history_id:t.history_id,sent_at,status:r.status,response:data,action:'Signed-out collection stopped. Spec section 3 permits collection in an authorized signed-in team browser; retain this response as historical evidence and do not retry restricted access in this context.'},null,2)+'\n');
        throw Error('Access restricted: '+r.status+' '+t.history_id+'; no login or bypass attempted');
      }
      if(r.status===200&&data.result===true) {extract(t,record);atomic(rawFile(t,verify),zlib.gzipSync(JSON.stringify(record)));return;}
      if(attempt===0&&(r.status===401||r.status===429||r.status>=500||r.status===0)) {
        await sleep(60000);await home();continue;
      }
      throw Error('History failed: HTTP '+r.status+' '+t.history_id);
    }
  }
  fs.mkdirSync(RAW,{recursive:true});
  try {
    await home();
    if(mode==='probe') {
      await pace();log({kind:'robots',sent_at:new Date(last).toISOString()});
      const r=await context.request.get('https://biggo.com.tw/robots.txt',{timeout:30000});
      const robots=await r.text();atomic(path.join(RAW,'robots.txt'),robots);if(r.status()!==200||!robots.includes('Disallow: /r/'))throw Error('Review changed robots.txt');
    }
    const chosen=mode==='probe'?Object.keys(SHOPS).map(p=>list.find(t=>t.platform===p&&t.coverage.class==='OK')):mode==='verify'?auditSample(list):list;
    const verify=mode==='verify';let count=0;
    for(const t of chosen) {
      if(fs.existsSync(rawFile(t,verify))) {extract(t,readRaw(rawFile(t,verify)));continue;}
      try{await history(t,verify);}
      catch(e){console.error(e.message);if(/Access restricted/.test(e.message))throw e;}
      count++;
      const summary=rebuild(list);
      if(verify)verifySaved(list);
      console.log(JSON.stringify({done:count,product_id:t.product_id,platform:t.platform,...summary}));
    }
    console.log('FINAL '+JSON.stringify(rebuild(list)));if(verify)verifySaved(list);
  } finally {try{rebuild(list);}finally{await browser.close();}}
}
if(require.main===module)collect(process.argv[2]||'collect').catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={parseCSV,itemID,tw,extract,visibleData,targets,rebuild,auditSample,verifySaved,HEADER,START,END};
