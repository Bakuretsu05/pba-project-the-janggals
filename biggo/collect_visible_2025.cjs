// UI collector used with the user's manually authenticated browser session.
// Start: node biggo/visible_checkpoint_server.cjs
// In the browser automation REPL, bind the signed-in BigGo tab and a second tab
// at http://127.0.0.1:8766/, then use this factory. No credentials are exported.
function createVisibleCollector(tab, checkpoint) {
  const state={last:0,pending:[]};
  const shops={momo:'tw_pec_momoshop',pchome:'tw_ec_pchome24h',coupang:'tw_pec_coupang'};
  async function pace() {
    const wait=5200-(Date.now()-state.last);
    if(wait>0)await tab.playwright.waitForTimeout(wait);
    state.last=Date.now();
  }
  async function plan() {
    return checkpoint.playwright.locator('#plan').evaluate(table=>
      [...table.querySelectorAll('tr')].slice(1).map(row=>({
        product_id:row.cells[0].innerText,platform:row.cells[1].innerText,
        item_id:row.cells[2].innerText,url:row.cells[3].querySelector('a').href,
        prior_points:Number(row.cells[4].innerText)
      })));
  }
  async function capture(target,verification=false) {
    if((await tab.url())!==target.url){await pace();await tab.goto(target.url);}
    if(await tab.playwright.getByRole('button',{name:'登入',exact:true}).count())
      throw Error('Session requires manual login; collection stopped');
    const history_id=shops[target.platform]+'-'+target.item_id;
    const row=tab.playwright.locator('div[class*="ProductItemListPC_product-row__"]')
      .filter({has:tab.playwright.locator('a[href*="id='+target.item_id+'"]')});
    try{await row.waitFor({state:'visible',timeoutMs:8000});}
    catch(error){
      if(await row.count())throw error;
      const missing={product_id:target.product_id,platform:target.platform,history_id,
        source:'biggo_visible_error',source_url:await tab.url(),
        sent_at:new Date(state.last).toISOString(),collected_at:new Date().toISOString(),verification,
        error:'Exact platform item ID '+target.item_id+' not present in product-table BigGo search results; no substitute listing used.'};
      state.pending.push(missing);return missing;
    }
    if(await row.count()!==1)throw Error('Ambiguous exact listing; inspect before continuing');
    await pace();const sent_at=new Date().toISOString();
    await row.locator('button[class*="PriceHistory_price-history-button__"]').click();
    await tab.playwright.getByRole('dialog').waitFor({state:'visible',timeoutMs:15000});
    let dialog=await tab.playwright.getByRole('dialog').innerText({timeoutMs:15000});
    const displayed=dialog.split('\n')[2];
    if(displayed&&!displayed.includes('最近2年')) {
      if(!target.catalog_variant)throw Error('Review catalog model/size/pack and supply catalog_variant before accepting '+history_id+' (default: '+displayed+')');
      if(displayed!==target.catalog_variant) {
        await tab.playwright.getByRole('dialog').getByText(displayed,{exact:true}).click();
        await tab.playwright.getByRole('menu').waitFor({state:'visible'});
        const option=tab.playwright.getByRole('menu').getByText(target.catalog_variant,{exact:true});
        if(await option.count()!==1)throw Error('Exact catalog variant unavailable; do not substitute');
        await pace();await option.click();
        await tab.playwright.getByRole('dialog').waitFor({state:'visible'});
        await pace(); // option label can update before its history finishes loading
        dialog=await tab.playwright.getByRole('dialog').innerText();
        if(dialog.split('\n')[2]!==target.catalog_variant)throw Error('Selected variant differs from catalog choice');
      }
    }
    if(!dialog.includes('最近2年'))throw Error('Two-year range is not selected; inspect before continuing');
    const record={product_id:target.product_id,platform:target.platform,history_id,
      source:'biggo_visible_table',sent_at,collected_at:new Date().toISOString(),
      source_url:await tab.url(),
      listing_url:await tab.playwright.getByRole('link',{name:'查看商品',exact:true}).getAttribute('href'),
      title:dialog.split('\n')[1],dialog_context:dialog.split('\n').slice(0,8),range:'最近2年',
      table:await tab.playwright.getByRole('table').innerText({timeoutMs:10000}),verification};
    if(target.catalog_variant)record.catalog_variant=target.catalog_variant;
    if(verification){await tab.getScreenshot();record.chart_visually_observed=true;}
    state.pending.push(record);
    await tab.playwright.getByRole('button',{name:'關閉',exact:true}).click();
    await tab.playwright.getByRole('dialog').waitFor({state:'hidden',timeoutMs:10000});
    return record;
  }
  async function save() {
    await checkpoint.playwright.getByRole('textbox',{name:'Public history evidence',exact:true})
      .fill(JSON.stringify({biggo_evidence_version:1,records:state.pending}));
    await checkpoint.playwright.getByRole('button',{name:'Save evidence',exact:true}).click();
    await checkpoint.playwright.getByRole('heading').waitFor({state:'visible',timeoutMs:10000});
    state.pending.length=0;
  }
  async function collect(targets,verification=false) {
    for(const target of targets){await capture(target,verification);await save();}
  }
  return {plan,capture,save,collect,state};
}
module.exports={createVisibleCollector};
