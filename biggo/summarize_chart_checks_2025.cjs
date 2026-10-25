const fs=require('node:fs'),zlib=require('node:zlib');
const c=require('./collect_2025.cjs'),dir=__dirname;
const read=f=>JSON.parse(zlib.gunzipSync(fs.readFileSync(f)));
const path=require('node:path');
const file=path.join(dir,'chart_checks_2025.csv');
const rows=c.parseCSV(fs.readFileSync(file,'utf8')).filter(r=>r.product_id==='3C-003'&&r.platform==='momo');
rows[0].note='Earlier signed-out visible-table check: all eight exported timestamps/prices matched.';
for(const t of c.targets()) {
 const base=path.join(dir,'raw/2025',t.product_id+'_'+t.platform);
 const candidate=fs.existsSync(base+'_catalog_variant.json.gz')?read(base+'_catalog_variant.json.gz'):null;
 const check=candidate?.verification?candidate:fs.existsSync(base+'_chart_verify.json.gz')?read(base+'_chart_verify.json.gz'):null;
 if(!check)continue;
 if(!check.chart_visually_observed)throw Error('No recorded chart observation: '+base);
 let result='match',note='Exact platform product ID checked; visible chart and two-year table reviewed. ';let n=0;
 if(check.catalog_variant_unavailable){result='catalog_variant_unavailable';note+=check.error;}
 else {
  const canonical=read(base+'.json.gz'),a=c.extract(t,canonical),b=c.extract(t,check);
  const vals=d=>d.rows.map(r=>[r.changed_at,r.price]);n=b.rows.length;
  if(JSON.stringify(vals(a))!==JSON.stringify(vals(b))) {
   const av=vals(a),bv=vals(b);
   if(av.length&&bv.length&&av[0][0]<'2025-10-01'&&bv[0][0]<'2025-10-01'&&av[0][1]===bv[0][1]&&JSON.stringify(av.slice(1))===JSON.stringify(bv.slice(1))&&a.rows[0].note.includes('earlier change time unknown')){result='baseline_window_clip';note+='Flat series first available observation moved from '+av[0][0]+' to '+bv[0][0]+' as two-year window advanced; price unchanged. Original baseline retained; actual earlier change time unknown. ';}
   else{result='discrepancy';note+='Current selected variant shows '+bv.length+' relevant rows versus '+av.length+' saved rows. Original records preserved; source coverage/variant discrepancy unresolved. ';}
  }else if(check.correction){result='corrected_variant_match';note+=check.correction_reason+'. Archived default evidence excluded. ';}
  if(check.catalog_variant)note+='Selected option: '+check.catalog_variant+'. ';
  else if(check.dialog_context?.[2]&&!check.dialog_context[2].includes('最近2年'))note+='Displayed option: '+check.dialog_context[2]+'. ';
  if(t.coverage.class!=='OK')note+='Prior '+t.coverage.class+': '+t.coverage.note;
 }
 rows.push({product_id:t.product_id,platform:t.platform,history_id:t.history_id,method:'Separate signed-in browser visit; exact listing; visible chart plus two-year displayed table',result,rows_checked:n,checked_on:c.tw(Date.parse(check.collected_at),true),note:note.trim()});
}
if(rows.length!==34)throw Error('Expected 34 completed listing reviews, got '+rows.length);
const header=['product_id','platform','history_id','method','result','rows_checked','checked_on','note'];
const quote=v=>/[",\r\n]/.test(String(v))?'"'+String(v).replace(/"/g,'""')+'"':String(v);
fs.writeFileSync(file,header.join(',')+'\n'+rows.map(r=>header.map(k=>quote(r[k])).join(',')).join('\n')+'\n');
console.log(JSON.stringify(rows.reduce((a,r)=>(a[r.result]=(a[r.result]||0)+1,a),{})));
