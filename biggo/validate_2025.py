"""CSV-only validation by default; --raw additionally verifies local source evidence."""
import argparse
import csv
import gzip
import io
import json
import re
from collections import Counter
from datetime import datetime, timezone, timedelta
from pathlib import Path
from urllib.parse import urlparse, parse_qs, urljoin

BASE = Path(__file__).resolve().parent
TW = timezone(timedelta(hours=8))
START = datetime(2025, 10, 1, tzinfo=TW)
END = datetime(2025, 11, 26, tzinfo=TW)
HEADER = ['product_id','platform','biggo_url','changed_at','price','entered_by','entered_on','note']
SHOPS = {'momo':'tw_pec_momoshop','pchome':'tw_ec_pchome24h','coupang':'tw_pec_coupang'}

def read(path):
    raw = path.read_bytes()
    text = raw.decode('utf-8', errors='strict')
    assert text.encode('utf-8') == raw, f'UTF-8 round-trip: {path}'
    assert '\ufffd' not in text, f'Replacement character: {path}'
    return list(csv.DictReader(io.StringIO(text.lstrip('\ufeff'), newline='')))

def item_id(platform, link, response_url=False):
    u = urlparse(link)
    if platform == 'momo':
        return parse_qs(u.query).get('i_code', [None])[0] or re.search(r'/product/(\d+)', u.path)[1]
    if platform == 'pchome':
        return re.search(r'/prod/([^/]+)', u.path)[1]
    if response_url and u.hostname=='coupang.onelink.me':
        query=parse_qs(u.query);ident=query['pageKey'][0]
        deep=parse_qs(urlparse(query['deep_link_value'][0]).query)
        assert ident.isdigit() and deep['pId']==[ident], 'Coupang referral identity mismatch'
        return ident
    return re.search(r'/products/(\d+)', u.path)[1]

def audit(base=BASE, raw=False):
    BASE=Path(base)
    products = read(BASE.parent / 'products/products.csv')
    old = {(r['product_id'],r['platform']): r for r in read(BASE/'coverage_check_2026-10-22.csv')}
    rows = read(BASE/'price_changes.csv')
    status=read(BASE/'collection_status_2025.csv')
    with (BASE/'price_changes.csv').open(encoding='utf-8', newline='') as f:
        assert next(csv.reader(f)) == HEADER, 'Exact section 11 header'
    assert len({tuple(r[c] for c in HEADER) for r in rows}) == len(rows), 'Duplicate complete records'
    targets={}
    for p in products:
        for platform, shop in SHOPS.items():
            if p['biggo_url_'+platform]:
                k=(p['product_id'],platform)
                assert k not in targets
                ident=item_id(platform,p[platform+'_url'])
                assert old[k]['history_id_used']==shop+'-'+ident
                targets[k]=(p,ident)
    assert Counter(k[1] for k in targets)=={'momo':150,'pchome':150,'coupang':35}
    grouped={k:[] for k in targets}
    for r in rows:
        assert set(r)==set(HEADER) and all(v is not None for v in r.values()), 'Invalid CSV row width'
        k=(r['product_id'],r['platform'])
        assert k in targets, 'Unknown product/platform'
        p, ident=targets[k]
        assert r['biggo_url']==p['biggo_url_'+r['platform']]
        assert re.fullmatch(r'\d{4}-\d\d-\d\d \d\d:\d\d',r['changed_at'])
        when=datetime.strptime(r['changed_at'],'%Y-%m-%d %H:%M').replace(tzinfo=TW)
        assert re.fullmatch(r'\d+',r['price'])
        assert r['entered_by']=='Albert'
        datetime.strptime(r['entered_on'],'%Y-%m-%d')
        assert r['note'], 'Missing note must be NA'
        assert when<END, 'No future-window rows'
        grouped[k].append(r)
    for k,listing_rows in grouped.items():
        times=[r['changed_at'] for r in listing_rows]
        assert times==sorted(times), f'Chronology: {k}'
        assert sum(t<'2025-10-01 00:00' for t in times)<=1, f'Extra baseline rows: {k}'
        assert all(a['price']!=b['price'] for a,b in zip(listing_rows,listing_rows[1:])), f'Consecutive equal prices: {k}'
        if old[k]['class']!='OK': assert all(old[k]['class'] in r['note'] for r in listing_rows)
    declared={(r['product_id'],r['platform']):r for r in status}
    assert len(declared)==len(status) and set(declared)==set(targets), 'Status inventory differs from targets'
    for k,r in declared.items():
        assert int(r['rows'])==len(grouped[k]), f'Status/CSV row count differs: {k}'
    verification=read(BASE/'verification_2025.csv') if (BASE/'verification_2025.csv').exists() else []
    chart_checks=read(BASE/'chart_checks_2025.csv') if (BASE/'chart_checks_2025.csv').exists() else []
    allowed={'match','corrected_variant_match','baseline_window_clip','discrepancy','catalog_variant_unavailable'}
    assert all(r['result'] in allowed for r in chart_checks), 'Unknown chart review result'
    assert not any(r['result']!='match' for r in verification), 'Unresolved repeat discrepancy'
    categories={category:sum(r['status']=='retrieved' and targets[k][0]['category']==category for k,r in declared.items()) for category in ['3C','APPL','BEAU','FOOD','HOME']}
    blocker=json.loads((BASE/'access_blocker_2025.json').read_text(encoding='utf-8')) if (BASE/'access_blocker_2025.json').exists() else None
    common={'target_listings':len(targets),'price_change_rows':len(rows),
            'attempted_listings':sum(r['status']!='not_attempted' for r in status),
            'all_listings_attempted':all(r['status']!='not_attempted' for r in status),
            'reported_retrieved':sum(r['status']=='retrieved' for r in status),
            'retrieved_counts_source':'collection_status_2025.csv (declared inventory)',
            'reported_retrieved_by_category':categories,
            'with_2025_records':sum(bool(r) for r in grouped.values()),
            'independently_retrieved_twice':len(verification),'independently_chart_checked':len(chart_checks),
            'chart_review_results':dict(Counter(r['result'] for r in chart_checks)),
            'unresolved_chart_reviews':[['_'.join((r['product_id'],r['platform'])),r['result']] for r in chart_checks if r['result'] in ('discrepancy','catalog_variant_unavailable')],
            'independent_verification_source':'saved audit records; no new website checks performed',
            'dataset_complete':all(r['status']=='retrieved' for r in status),
            'login_blocker':blocker}
    if not raw:
        return {**common,'validation_mode':'csv_only','raw_to_csv_verified':False,
                'tests':'PASS (CSV schema, identifiers, chronology, prices, metadata, duplicates, date window, UTF-8 and inventory consistency)',
                'not_verified':'Source history completeness, UTC timestamp conversion, actual collection dates and request pacing require --raw and local evidence.'}
    required={k for k,r in declared.items() if r['status'] in ('retrieved','empty') or grouped[k]}
    absent=[k for k in required if not (BASE/'raw/2025'/('_'.join(k)+'.json.gz')).is_file()]
    assert not absent, f'Full raw verification unavailable: missing evidence for {len(absent)} collected listings. Use CSV-only validation or restore the evidence bundle.'
    assert (BASE/'raw/2025/requests.jsonl').is_file(), 'Full raw verification unavailable: missing requests.jsonl. Use CSV-only validation or restore the evidence bundle.'
    # Failed searches/excluded variants need attempt evidence too, without
    # turning their displayed prices into accepted history records.
    for k,r in declared.items():
        if r['status']!='failed':continue
        file=BASE/'raw/2025'/('_'.join(k)+'.json.gz')
        assert file.is_file(), f'Missing failed-attempt evidence: {k}'
        with gzip.open(file,'rt',encoding='utf-8') as f: failed=json.load(f)
        assert failed['source']=='biggo_visible_error' and failed['error']
        assert failed['product_id']==k[0] and failed['platform']==k[1]
        assert failed['history_id']==SHOPS[k[1]]+'-'+targets[k][1]
    checked=0; expected_rows=0; missing=[]; issues=[]; counts=Counter(); prior_differences=[]; sources=Counter()
    for k,(p,ident) in targets.items():
        file=BASE/'raw/2025'/('_'.join(k)+'.json.gz')
        if k not in required: missing.append(k); continue
        with gzip.open(file,'rt',encoding='utf-8') as f: record=json.load(f)
        visible=record.get('source')=='biggo_visible_table'
        if visible:
            assert record['range']=='最近2年'
            assert record['product_id']==k[0] and record['platform']==k[1]
            link=urlparse(urljoin('https://biggo.com.tw',record['listing_url']))
            query=parse_qs(link.query)
            assert link.hostname=='biggo.com.tw' and query['id']==[ident] and query['i']==[SHOPS[k[1]]]
            assert item_id(k[1],query['purl'][0],response_url=True)==ident
            visible_points=[]
            for line in record['table'].splitlines():
                if line.startswith('現在\t'):continue
                match=re.match(r'^(\d{4}-\d\d-\d\d \d\d:\d\d)\t\$([\d,]+)\t',line)
                assert match, 'Invalid visible table row'
                when=datetime.strptime(match[1],'%Y-%m-%d %H:%M').replace(tzinfo=TW)
                visible_points.append({'x':int(when.timestamp()*1000),'y':int(match[2].replace(',',''))})
            d={'title':record['title'],'result':True,'history_id':record['history_id'],'oid':ident,'nindex':SHOPS[k[1]],'price_history':list(reversed(visible_points))}
            sources['visible_table_tw_minute']+=1
        else:
            d=record['data'];assert record['status']==200
            sources['api_utc_milliseconds']+=1
        assert isinstance(d['title'],str) and '\ufffd' not in d['title']
        assert d['title'].encode('utf-8').decode('utf-8')==d['title'], 'Chinese title round-trip'
        assert d['result'] is True
        assert d['history_id']==SHOPS[k[1]]+'-'+ident
        assert d['oid']==ident and d['nindex']==SHOPS[k[1]]
        points=sorted(d['price_history'],key=lambda p:p['x'])
        period=[q['y'] for q in points if START.timestamp()*1000<=q['x']<END.timestamp()*1000]
        previous=old[k]
        if len(period)!=int(previous['n_points_2025_10_01_to_11_25']) or (period and (min(period)!=int(previous['min_price_in_period']) or max(period)!=int(previous['max_price_in_period']))):
            prior_differences.append(k)
        events=[]
        for q in points:
            assert type(q['x']) is int and type(q['y']) is int and q['y']>=0
            when=datetime.fromtimestamp(q['x']/1000,timezone.utc).astimezone(TW)
            if not events or q['y']!=events[-1][1]: events.append((when,q['y']))
        before=[e for e in events if e[0]<START][-1:]
        selected=before+[e for e in events if START<=e[0]<END]
        expect=[(when.strftime('%Y-%m-%d %H:%M'),str(price)) for when,price in selected]
        actual=[(r['changed_at'],r['price']) for r in grouped[k]]
        assert expect==actual, f'Independent raw-to-CSV mismatch: {k}'
        assert actual==sorted(actual,key=lambda r:r[0]), f'Chronology: {k}'
        assert sum(r['changed_at']<'2025-10-01 00:00' for r in grouped[k])<=1
        date=datetime.fromisoformat(record['collected_at'].replace('Z','+00:00')).astimezone(TW).strftime('%Y-%m-%d')
        assert all(r['entered_on']==date for r in grouped[k]), 'Actual collection date'
        if old[k]['class']!='OK': assert all(old[k]['class'] in r['note'] for r in grouped[k])
        if not before: counts['without_preperiod_baseline']+=1
        if points and datetime.fromtimestamp(points[-1]['x']/1000,TW)<END-timedelta(minutes=1):
            counts['tracking_ends_before_window_end']+=1
            assert all('do not carry' in r['note'] for r in grouped[k])
        if selected: counts['with_2025_records']+=1
        if any(START<=e[0]<END for e in events): counts['with_in_window_changes']+=1
        if old[k]['class'] in ('MISMATCH','UNCERTAIN'): issues.append(k)
        expected_rows+=len(selected);checked+=1
    assert expected_rows==len(rows), 'All rows accounted for'
    logs=[json.loads(line) for line in (BASE/'raw/2025/requests.jsonl').read_text().splitlines()]
    if (BASE/'raw/2025/browser_actions.jsonl').exists():
        logs += [json.loads(line) for line in (BASE/'raw/2025/browser_actions.jsonl').read_text().splitlines()]
        logs.sort(key=lambda r:r['sent_at'])
    sent=[datetime.fromisoformat(r['sent_at'].replace('Z','+00:00')).timestamp() for r in logs]
    gaps=[b-a for a,b in zip(sent,sent[1:])]
    assert all(g>=5 for g in gaps), 'Request spacing under 5 seconds'
    restrictions=[r for r in logs if r.get('require_login')]
    result={**common,'validation_mode':'raw_to_csv','raw_to_csv_verified':True,
            'attempt_evidence_verified':sum(r['status']=='failed' for r in status)+checked,
            'source_evidence_counts':dict(sources),
            'target_listings':len(targets),'retrieved':checked,'price_change_rows':len(rows),
            'independently_retrieved_twice':len(verification),'missing':missing,
            'independently_chart_checked':len(chart_checks),
            'prior_ambiguous_or_mismatched_listings':len(issues),
            'minimum_logged_request_gap_seconds':round(min(gaps),3) if gaps else None,
            'dataset_complete':not missing,
            'access_restrictions':restrictions,
            'differences_from_prior_2025_point_counts_or_extrema':prior_differences,
            'tests':'PASS (raw-to-CSV comparison covers every retrieved listing)',**dict(counts)}
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw',action='store_true',help='Require local raw histories and request log; reconstruct all collected records')
    parser.add_argument('--output',type=Path,help='Explicitly save a JSON report; default is read-only stdout')
    args=parser.parse_args()
    try:
        result=audit(raw=args.raw)
    except (AssertionError,OSError,ValueError,KeyError) as error:
        parser.exit(1,f'Validation failed: {error}\n')
    display={**result}
    if 'missing' in display:
        display['missing_count']=len(display['missing'])
        if len(display['missing'])>=10: display['missing']='See collection_status_2025.csv'
    print(json.dumps(display,ensure_ascii=False,indent=2))
    if args.output:args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
