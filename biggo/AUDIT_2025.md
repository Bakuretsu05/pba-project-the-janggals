# 2025 BigGo collection audit — all targets attempted, gaps remain

Albert collected the data on **2026-10-25 and 2026-10-26, Taiwan time (UTC+8)**.
This continues draft PR #11 from `b1c5e77d9f576ee5a794c7dc7e758d01b00677c4`.
Collection/review continued after midnight; dates were not backdated to the Oct 25
milestone deadline. **Milestone 2 remains incomplete:** five listings remain without accepted collected
history, and independent review retains unresolved findings.

## Executed results

Targets attempted means processed by the collection workflow, including exact-ID
UI search attempts. It does not mean 335 exact history endpoint requests were made.

| Platform | Targets attempted | Accepted histories | With relevant 2025 records | CSV rows |
|---|---:|---:|---:|---:|
| momo | 150 | 149 | 148 | 917 |
| pchome | 150 | 147 | 147 | 873 |
| coupang | 35 | 34 | 32 | 1077 |
| Total | 335 | 330 | 327 | 2867 |

“Relevant” means an observed in-window change or a preceding observed baseline;
it does not certify correct physical variant, uninterrupted tracking or complete
period coverage. Of the accepted histories, 233 contain an actual in-window change.
Three accepted series have no usable 2025 observation: 3C-002 momo, FOOD-004 Coupang
and HOME-009 Coupang. Their selected current variants have only later history;
no 2025 rows were invented from another option.

| Category | Original retrieved | Current accepted |
|---|---:|---:|
| Electronics (3C) | 72 | 72 |
| Appliances (APPL) | 44 | 67 |
| Beauty (BEAU) | 0 | 63 |
| Food (FOOD) | 0 | 66 |
| Home (HOME) | 0 | 62 |

The original 116-listing partial bundle covered **Electronics and Appliances only**,
with zero Beauty, Food or Home histories. Its **1,397 rows remain byte-for-byte
unchanged as the first 224,745 bytes** of the expanded CSV. Their SHA-256 is
`6a888791005a1a6818f01753e5bccfdcdf764446f184fb350a9c14cc08851842`.
The final CSV has 748,126 bytes and SHA-256
`b684d8e7ae09294867003c6c67fcce97542452f8acf6b5514d8bbac56a7e46a1`.
Full-evidence rebuild produced identical final bytes. CSV LF line endings are
explicitly pinned for fresh checkouts.

## Authorization and retained login blocker

The original signed-out collector stopped at **2026-10-25 20:50:03.094 Taiwan time**:

```text
POST https://biggo.com.tw/api/v1/spa/product/history
{"history_id":"tw_pec_momoshop-6198895","days":730}
HTTP 429
{"result":false,"require_login":true}
```

`access_blocker_2025.json` and `raw/2025/APPL-019_momo_attempt1.json.gz` remain
unchanged. The original no-login decision applied to that partial delivery.
The user subsequently explicitly reported team approval and authorized authenticated
collection using their own account; see `collection_authorization_2025.md`.
Specification section 3 itself was **not modified**. The signed-out HTTP collector
still refuses online collection while the marker exists.

The user manually signed into the in-app browser after the separate Chrome login
failed. APPL-019 momo then displayed real history. The remaining 219 listings were
attempted through ordinary UI controls in that authorized session. No passwords,
cookies, JWTs or session tokens were read/exported. No authentication, CAPTCHA or
rate-limit bypass was used. Source redirect links were read for identity without
following `/r/`.

The dedicated signed-out collector reused the configured team contact in its
study user agent. The authenticated in-app browser retained its ordinary browser
identity because custom user-agent configuration was unavailable. The contact is
kept only in ignored configuration and excluded from Git and the evidence bundle.
Controlled BigGo navigations, history openings, retries and option changes were
paced at least 5.2 seconds apart. The combined logged history-action minimum is
5.199 seconds. Browser asset requests are not individually controlled or logged.
The earlier setup diagnostic's homepage/robots calls were not included in that
paced log; history-to-history collection requests were paced.

## Five listings without usable evidence

| Listing | Reason |
|---|---|
| APPL-020 momo | Exact platform item ID absent in original and focused-title searches |
| APPL-020 pchome | Exact platform item ID absent in original and focused-title searches |
| BEAU-020 pchome | Exact platform item ID absent in original and focused-title searches |
| FOOD-002 pchome | Exact platform item ID absent in original and focused-title searches |
| HOME-013 coupang | Exact listing defaults to 500ml; catalog asks for 750ml x1; no confirmed matching option |

The first four are search misses, not proven endpoint failures. Marvin's Oct 22
report records successful HTTP 200 histories for all four. Their exact authenticated
endpoint availability was not tested by the UI-only continuation.

Initial exact-ID searches missed 29 listings. One focused retry per listing using
the prior recorded title recovered 25. Four remained absent; no first-result or
other-product substitution was made. HOME-013 was separately excluded during
variant review. Attempt/error evidence is saved for every one of the 335 targets.
All target statuses, including zero-row series, remain explicit in
`collection_status_2025.csv`.

## Independent chart review and variant corrections

**34 distinct listings were reviewed**: 33 separate authenticated browser visits,
plus the earlier signed-out 3C-003 momo review. The sample spans all five categories
and all platforms, prioritizing summary differences, selectable Coupang variants,
SHORT histories, the known mismatch and stopped series. `chart_checks_2025.csv`
records actual results, not a blanket success claim:

| Review result | Listings |
|---|---:|
| Exact saved timestamp/price match | 25 |
| Catalog variant corrected and accepted with chart/table review | 6 |
| Flat baseline qualified by moving-window boundary | 1 |
| Unresolved saved-history discrepancy | 1 |
| Catalog option unconfirmed; excluded | 1 |

The six corrected newly collected Coupang histories are BEAU-007 (150ml x2),
BEAU-012 (300ml x4), FOOD-009 (330ml x24), FOOD-010 (330ml x48), FOOD-011 (580ml
x24), and FOOD-020 (62g x10). The correct listing ID had initially opened a
nonmatching default size/pack. Only those new rows were replaced via an explicit
correction command requiring the protected original snapshot hash. Earlier
wrong-option evidence is archived; `variant_corrections_2025.json` records the
changes. HOME-013's single-bottle review still showed 500ml, so its final disposition
is exclusion, not acceptance of that attempted correction. The option-selection
factory now requires an explicit catalog option before accepting a selectable SKU.
A separate post-correction network retrieval of each corrected option is not claimed.

The targeted follow-up below qualifies these findings. Two reviews require further resolution:

- **3C-010 momo:** the catalog's gray option currently shows only 2026 points,
  whereas the saved original API evidence has six 2025 changes. Both default blue
  and selected gray were inspected. The UI identity is exact but coverage differs.
  All six original rows remain intact, flagged SHORT; the unresolved discrepancy
  is explicit in the chart report and status note. Do not call this verified history.
- **HOME-013 Coupang:** the catalog's 750ml single-bottle option was not confirmed.
  The 500ml history is excluded; the source mismatch remains unresolved.

For **3C-004 PChome**, the constant NT$590 series' first visible observation moved
from 2024-10-25 20:40 to 2024-10-26 00:07 with the moving two-year window. The
original baseline is retained, with its existing warning that the real earlier
change time is unknown. This is a qualified comparison, not an exact timestamp match.

The known **APPL-003 Coupang pink/blue mismatch** remains: the chart matches the
saved pink EH-NE57-P history, while the catalog specifies blue EH-NE57-A. Its 30
original rows retain MISMATCH warnings and cannot establish blue-variant prices.
Other original UNCERTAIN flags remain unresolved. Independent verification has
completed its sample review count, but unresolved findings prevent clean sign-off.
`verification_2025.csv` remains header-only because the old direct-API repeat plan
was not executed; visible-chart reviews are recorded separately.

## Coverage and precision limitations

Twelve accepted histories have **no observed pre-Oct-1 baseline**: 3C-002 momo;
3C-010 momo/pchome; 3C-011 momo/pchome; APPL-010 pchome; APPL-020 coupang;
FOOD-004 coupang; FOOD-007 pchome; HOME-009 coupang; HOME-016 momo/pchome.
Nine of these contribute 2025 rows; the other three are the zero-row series above.
Series first seen on Oct 1 also have no earlier baseline.

Fourteen accepted series stop before the window ends. Their row notes explicitly
say not to carry the last price through Nov 25 without evidence. All eight original
SHORT, one MISMATCH and 38 UNCERTAIN classifications remain in the inventory;
current selected variants can have different coverage from those earlier summaries.
Twenty-one accepted histories differ from the Oct 22 point-count or min/max
summaries. Each is flagged in row/status notes and listed in `validation_2025.json`.
A stable current UI recheck does not resolve which earlier variant was summarized.

Original evidence comprises 116 API histories with UTC millisecond timestamps.
Continuation evidence comprises 214 accepted visible tables displaying Taiwan
minute timestamps. The two sources are distinguished explicitly. Visible timestamps
are parsed as UTC+8, without claiming access to hidden milliseconds or HTTP status.
Only consecutive equal observations collapse. Reversals remain, including distinct
same-minute changes with their source order in notes. The last real preceding
change is the baseline; no daily values are filled. The CSV contains only the 2025
study period plus baselines. Full two-year source evidence is not a 2026 dataset.

## Validation and reproduction

- **23/23 Node tests passed**, including missing/empty/partial/corrupt/truncated
  raw evidence, missing raw for a zero-row retrieved series, successful fixture
  rebuild, visible timestamps/identity, and protected-original correction refusal.
- **9/9 Python tests passed**, including fresh-checkout CSV-only validation,
  explicit raw-mode failure without evidence, malformed data rejection and honest
  reporting of unresolved chart findings. Windows sandbox temporary-file rename
  restrictions required running the test suites outside that sandbox.
- `python biggo/validate_2025.py`: CSV-only validation passes and is read-only.
- `python biggo/validate_2025.py --raw`: all **330 accepted histories and 2,867 rows**
  pass independent raw-to-CSV reconstruction; all **335 attempt records** are
  accounted for. Saved source verification does not resolve physical variants or
  independently prove that the website exposes every historical event.
- `node biggo/collect_2025.cjs rebuild`: final CSV is byte-for-byte unchanged;
  original 1,397-row prefix hash remains unchanged. The explicit correction path
  did not touch those original rows.

In a fresh Git checkout, CSV-only validation requires no raw directory. Rebuild
and `--raw` fail clearly without the ignored evidence and preserve the populated
CSV/status files. Restore the evidence bundle's `biggo/raw/2025/` for full offline
reconstruction. The committed `validation_2025.json` describes the executed local
full-evidence run; it does not imply that raw files are committed.

Only BigGo deliverables/scripts/tests/docs are changed. The product catalog,
project specification, ignored contact configuration and browser profiles are not
part of the PR. Draft PR #11 targets main and must not be merged by this task.

## Final targeted QC, 2026-10-26

[TARGETED_QC_2026-10-26.md](TARGETED_QC_2026-10-26.md) and
`targeted_qc_2026-10-26.json` record the bounded follow-up. No prices or CSV rows
changed. Four historical HTTP 200 successes are confirmed, but exact POST recovery
could not be executed through the available signed-in browser tool. Those four
remain unretrieved, with current endpoint availability untested. Two exact-ID UI
histories were reopened with 5.2-second controlled pacing; no broad search was
repeated. One exact Coupang SKU detail link was denied, so no retry was made.

The SSD raw parent response lists separate blue/gray child history IDs. The selected-variant UI table may have a different scope from
that parent series. This is a plausible explanation, not a proven wire-level cause:
the actual UI request ID was not observable, and the six parent changes are not
thereby established as gray prices. The original rows and warning remain. The pink/blue mismatch is confirmed
from the saved model/title; no blue replacement is established. HOME-013's selected
visible item/vendor IDs differ from the catalog IDs, and the generic single-bottle
label does not confirm 750ml. It remains excluded rather than claimed unavailable
in every history representation.

Authorization wording now attributes team approval to the user's explicit earlier
statement; no independent team decision record was reviewed. This is a factual
attribution clarification, not a withdrawal of the user's authorized scope.

Following this targeted pass, all 23 Node and nine Python tests were rerun and
passed. CSV-only validation, full raw reconstruction and byte-identical offline
rebuild passed again. No software rewrite or new test framework was needed.
