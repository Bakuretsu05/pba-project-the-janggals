// Local-only checkpoint form for public price-table evidence from the authorized browser.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib');
const root=path.resolve(__dirname,'..');
const c=require(path.join(root,'biggo/collect_2025.cjs'));
const list=c.targets(),raw=path.join(root,'biggo/raw/2025');
let saved=0;
const canonical=t=>path.join(raw,t.product_id+'_'+t.platform+'.json.gz');
const load=file=>JSON.parse(zlib.gunzipSync(fs.readFileSync(file)).toString('utf8'));
function reviewPlan() {
  const checked=new Set(c.parseCSV(fs.readFileSync(path.join(root,'biggo/chart_checks_2025.csv'),'utf8')).map(r=>r.product_id+'_'+r.platform));
  if(checked.size>=34)return [];
  const changed=list.filter(t=>fs.existsSync(canonical(t))&&load(canonical(t)).source!=='biggo_visible_error'&&c.extract(t,load(canonical(t))).note.includes('differs from prior coverage summary'));
  const ranked=[...changed,...c.auditSample(list),...list];
  const seen=new Set(),chosen=[];
  for(const t of ranked){const k=t.product_id+'_'+t.platform;if(seen.has(k)||checked.has(k)||!fs.existsSync(canonical(t)))continue;seen.add(k);if(load(canonical(t)).source==='biggo_visible_error')continue;chosen.push(t);if(chosen.length>=34-checked.size)break;}
  return chosen.filter(t=>!fs.existsSync(path.join(raw,t.product_id+'_'+t.platform+'_chart_verify.json.gz')));
}
const server=http.createServer((req,res)=>{
  if(req.method==='GET') {
    const pending=req.url==='/audit'?reviewPlan():req.url==='/retry'?list.filter(t=>fs.existsSync(canonical(t))&&load(canonical(t)).source==='biggo_visible_error'):list.filter(t=>!fs.existsSync(canonical(t)));
    const retry=req.url==='/retry';
    const plan=pending.map(t=>{let u=new URL(t.biggo_url);if(retry)u.pathname='/s/'+encodeURIComponent(t.coverage.title)+'/';if(req.url==='/audit'){const record=load(canonical(t));if(record.source==='biggo_visible_table')u=new URL(record.source_url);else u.pathname='/s/'+encodeURIComponent(record.data.title)+'/';}return '<tr><td>'+t.product_id+'</td><td>'+t.platform+'</td><td>'+t.platform_item_id+'</td><td><a href="'+u.href.replace(/&/g,'&amp;')+'">Search</a></td><td>'+t.coverage.n_points+'</td></tr>';}).join('');
    res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><title>BigGo local evidence checkpoint</title><h1>BigGo evidence checkpoint</h1><p>Saved this session: '+saved+'</p><form method="post"><label>Public history evidence<textarea name="evidence" rows="8" cols="80"></textarea></label><button>Save evidence</button></form><table id="plan"><tr><th>Product</th><th>Platform</th><th>Item ID</th><th>Source</th><th>Prior points</th></tr>'+plan+'</table>');return;
  }
  if(req.method!=='POST'){res.writeHead(405);res.end();return;}
  let body='';req.on('data',chunk=>{body+=chunk;if(body.length>5000000)req.destroy();});
  req.on('end',()=>{
    try {
      const payload=JSON.parse(new URLSearchParams(body).get('evidence'));
      if(payload.biggo_evidence_version!==1||!Array.isArray(payload.records))throw Error('Wrong evidence format');
      for(const record of payload.records) {
        const target=list.find(t=>t.history_id===record.history_id);if(!target)throw Error('Unknown listing');
        const data=record.source==='biggo_visible_error'?{points:[],rows:[]}:c.extract(target,record);
        const file=path.join(raw,target.product_id+'_'+target.platform+(record.correction?'_catalog_variant':record.verification?'_chart_verify':'')+'.json.gz');
        if(fs.existsSync(file)) {
          if(load(file).source!=='biggo_visible_error')throw Error('Refusing to overwrite existing valid evidence');
          const archive=file.replace('.json.gz','_initial_search_failure.json.gz');
          if(!fs.existsSync(archive))fs.copyFileSync(file,archive);
        }
        fs.writeFileSync(file+'.tmp',zlib.gzipSync(JSON.stringify(record)));fs.renameSync(file+'.tmp',file);saved++;
        if(record.sent_at)fs.appendFileSync(path.join(raw,'browser_actions.jsonl'),JSON.stringify({kind:record.verification?'chart_verify':'visible_history',history_id:target.history_id,sent_at:record.sent_at,outcome:record.error?'missing_exact_listing':'table_saved'})+'\n');
        console.log(JSON.stringify({saved:target.history_id,points:data.points.length,rows:data.rows.length,verification:!!record.verification}));
      }
      console.log(JSON.stringify(c.rebuild(list)));
      res.writeHead(303,{Location:'/'});res.end();
    }catch(error){console.error(error.message);res.writeHead(400,{'Content-Type':'text/plain; charset=utf-8'});res.end(error.message);}
  });
});
server.listen(8766,'127.0.0.1',()=>console.log('BigGo public-evidence checkpoint ready at http://127.0.0.1:8766'));
