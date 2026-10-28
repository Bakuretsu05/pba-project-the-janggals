// Explicit, audited correction of newly collected default-option histories.
// Supply a recognized preserved snapshot. September insertion means protection
// compares record fields, not a byte prefix; window-dependent notes may differ.
const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib'),crypto=require('node:crypto');
const c=require('./collect_2025.cjs');
function apply(protectedFile,dir=__dirname) {
  const protectedBytes=fs.readFileSync(protectedFile);
  const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
  const preservation=JSON.parse(fs.readFileSync(path.join(dir,'preservation_2025.json'),'utf8'));
  if(!preservation.protected_snapshot_sha256.includes(hash(protectedBytes)))throw Error('Wrong protected CSV snapshot');
  const file=path.join(dir,'price_changes.csv'),before=fs.readFileSync(file);
  const rows=c.parseCSV(before.toString('utf8')),protectedRows=c.parseCSV(protectedBytes.toString('utf8'));
  assertProtected(protectedRows,rows);
  const raw=path.join(dir,'raw/2025'),list=c.targets(),changes=[],replacements=new Map();
  const read=f=>JSON.parse(zlib.gunzipSync(fs.readFileSync(f)).toString('utf8'));
  for(const target of list) {
    const key=target.product_id+'_'+target.platform,candidate=path.join(raw,key+'_catalog_variant.json.gz');
    if(!fs.existsSync(candidate))continue;
    if(fs.existsSync(path.join(raw,key+'.json.gz'))&&fs.readFileSync(candidate).equals(fs.readFileSync(path.join(raw,key+'.json.gz'))))continue;
    if(protectedRows.some(r=>r.product_id===target.product_id&&r.platform===target.platform))throw Error('Correction may not change the protected collection');
    const record=read(candidate);
    if(!record.correction||!record.catalog_variant||!record.correction_reason)throw Error('Missing explicit catalog-variant correction evidence');
    const excluded=record.catalog_variant_unavailable===true;
    if(excluded&&!(record.source==='biggo_visible_error'&&record.history_id===target.history_id&&record.product_id===target.product_id&&record.platform===target.platform&&record.observed_options?.length&&record.error))throw Error('Invalid catalog exclusion evidence');
    const replacement=excluded?[]:c.extract(target,record).rows;
    const oldRows=rows.filter(r=>r.product_id===target.product_id&&r.platform===target.platform);
    replacements.set(key,replacement);changes.push({product_id:target.product_id,platform:target.platform,old_rows:oldRows.length,new_rows:replacement.length,selected_variant:record.catalog_variant,excluded,reason:record.correction_reason});
  }
  if(!changes.length)return [];
  const output=[];
  for(const target of list){const key=target.product_id+'_'+target.platform;output.push(...(replacements.get(key)||rows.filter(r=>r.product_id===target.product_id&&r.platform===target.platform)));}
  const quote=v=>/[",\r\n]/.test(String(v))?'"'+String(v).replace(/"/g,'""')+'"':String(v);
  const bytes=Buffer.from(c.HEADER.join(',')+'\n'+output.map(r=>c.HEADER.map(k=>quote(r[k])).join(',')).join('\n')+'\n','utf8');
  assertProtected(protectedRows,output);
  fs.writeFileSync(path.join(raw,'variant_correction_manifest.json'),JSON.stringify({before_sha256:hash(before),after_sha256:hash(bytes),protected_sha256:hash(protectedBytes),changes},null,2)+'\n');
  for(const change of changes){const key=change.product_id+'_'+change.platform,canonical=path.join(raw,key+'.json.gz'),archive=path.join(raw,key+'_excluded_default_option.json.gz');if(!fs.existsSync(archive))fs.copyFileSync(canonical,archive);fs.copyFileSync(path.join(raw,key+'_catalog_variant.json.gz'),canonical);}
  fs.writeFileSync(file+'.tmp',bytes);fs.renameSync(file+'.tmp',file);
  // An explicit catalog exclusion also withdraws the prior retrieved claim.
  // Ordinary rebuild cannot make this decision or remove any existing records.
  const statusFile=path.join(dir,'collection_status_2025.csv');
  if(changes.some(r=>r.excluded)) {
    const status=c.parseCSV(fs.readFileSync(statusFile,'utf8'));
    for(const row of status)if(changes.some(r=>r.excluded&&r.product_id===row.product_id&&r.platform===row.platform)){row.status='failed';row.rows='0';row.note=changes.find(r=>r.product_id===row.product_id&&r.platform===row.platform).reason;}
    const columns=Object.keys(status[0]);
    fs.writeFileSync(statusFile,columns.join(',')+'\n'+status.map(r=>columns.map(k=>quote(r[k])).join(',')).join('\n')+'\n');
  }
  c.rebuild(list);
  const report=path.join(dir,'variant_corrections_2025.json');
  const previous=fs.existsSync(report)?JSON.parse(fs.readFileSync(report,'utf8')):[];
  fs.writeFileSync(report,JSON.stringify([...previous,...changes],null,2)+'\n');
  return changes;
}
if(require.main===module){try{if(!process.argv[2])throw Error('Supply the original pre-authentication CSV snapshot');console.log(JSON.stringify(apply(process.argv[2])));}catch(e){console.error(e.message);process.exitCode=1;}}
function assertProtected(protectedRows,rows) {
  const key=r=>JSON.stringify(c.HEADER.filter(k=>k!=='note').map(k=>String(r[k]))),counts=new Map();
  for(const r of rows)counts.set(key(r),(counts.get(key(r))||0)+1);
  for(const r of protectedRows){const k=key(r);if(!counts.get(k))throw Error('Protected price record has changed or is missing');counts.set(k,counts.get(k)-1);}
}
module.exports={apply,assertProtected};
