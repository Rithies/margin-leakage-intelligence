# Design decisions

A log of the design choices in this project: what I decided, why, and what I gave up.
Newest phase at the bottom.

---

## Phase 0 — Setup

### D-01 · Git repo holds only my own work
- **Decision:** the repo contains my SQL, Power BI project files (PBIP) and docs. Raw data and mentor/AI notes stay outside it.
- **Why:** the repo is my portfolio. Everything in it should be something I built and can explain.

### D-02 · No feature branches or pull requests on a solo repo
- **Decision:** I commit straight to `main`. The GitHub "protect main" rule was switched off.
- **Why:** PRs exist so a second person can review a change. Working alone, they only add ceremony.
- **Trade-off:** I lose the review step. I plan one real PR in Phase 4 to show a TMDL measure diff.

---

## Phase 1 — SQL layer

### D-03 · Split the sources: ERP/finance/masters in PostgreSQL, shop-floor files stay files
- **Decision:** jobs, quotes, invoices, credit notes, receipts, FX and masters go into PostgreSQL. MES machine logs, stores, QA and the Excel files (budget, rate card) are read directly by Power Query.
- **Why:** this mirrors a real company (ERP = database, shop floor = exported files) and lets me show both SQL and query folding.

### D-04 · Four schemas by layer and domain
- **Decision:** `raw` (landing), `erp`, `finance`, `masters` (typed).
- **Why:** you can tell from the name where a table came from and whether it has been typed yet.

### D-05 · Land raw data as TEXT with no constraints
- **Decision:** every column in `raw` is TEXT, with no keys and no NOT NULLs.
- **Why:** the load can never reject a row, so nothing is silently lost. Problems are found in the next layer, where they can be counted.

### D-06 · The typed layer changes types, not values
- **Decision:** `02_typed_layer.sql` only casts (dates, integers, numerics, booleans) and turns blanks into NULL with `NULLIF`. It does not trim, rename, de-duplicate or fix anything.
- **Why:** cleaning belongs in Power Query as documented, reusable rules. If SQL also cleaned, the fixes would be split across two places.

### D-07 · Strict casts, fail loudly
- **Decision:** casts are strict and the whole script runs in one transaction (`BEGIN … COMMIT`). One bad value stops everything and rolls back.
- **Why:** a loud failure is better than a quiet wrong number. A typed table that loads is guaranteed to be complete.
- **Trade-off:** a single bad cell blocks the load. The alternative (a quarantine table for bad rows) wasn't needed for this data.

### D-08 · Typed row count must equal raw row count
- **Decision:** `02_typed_layer.sql` ends with a check for all 19 tables (raw rows = typed rows, every row "OK").
- **Why:** typing must never add or lose rows.

### D-09 · The repo rebuilds from scratch: `00_setup.sql`
- **Decision:** schema creation is a script (`CREATE SCHEMA IF NOT EXISTS …`), not something I typed by hand once.
- **Why:** anyone who clones the repo can run 00 → 01 → 02 → 03 on a fresh PostgreSQL install.

### D-10 · Profile before building: `03_profiling.sql`
- **Decision:** a read-only scorecard of 100 checks across all 19 tables, in five families: volume, uniqueness, completeness, integrity (orphans), validity.
- **Pattern:** every check counts the rows that **break** a rule, so 0 = PASS. Each row is labelled `zero` (a rule) or `info` (a fact to watch, never graded). FAILs sort to the top.
- **Why:** row counts only prove data loaded, not that it's true. This is the same pattern my Power Query `05 Validation` queries will use.

### D-11 · Check tolerances must match the source's rounding
- **Decision:** cost-element sum checked within ₹5 (8 elements, each rounded to whole rupees); board cost = kg × price/kg checked within 0.1% (kg rounded to 0.1).
- **Why:** a ₹1 tolerance flagged thousands of correct rows. A check that cries wolf gets ignored. I never loosen a tolerance to hide a real problem, only to match how the source rounds.

### D-12 · GST checks apply to INR invoices only
- **Decision:** "GST = 18% of taxable value" is tested on INR invoices. USD invoices are tested for GST = 0.
- **Why:** the 222 USD invoices are exports, which are zero-rated.

### D-13 · Customer de-duplication keys on GSTIN, not on the code's name
- **Evidence:** 3 real customers each have two codes (same GSTIN): C008 / C008-OLD, C010 / C110, C036 / C136. **C110 and C136 have no "-OLD" suffix.** All 5 profiling FAILs trace back to these 3 legacy codes: jobs on the legacy code vs SKU/quote on the current one (430 / 407), credit notes on the current code vs invoices on the legacy one (22), and lowercase sales-rep codes (sr01/sr02) on the legacy rows (3).
- **Decision:** in Phase 2, map legacy codes to current codes using GSTIN plus an explicit mapping file.
- **Why:** a rule that looks for "-OLD" would miss C110. GSTIN identifies the legal entity.

### D-14 · Dim Date covers whole financial years: 1-Apr-2024 to 31-Mar-2027
- **Evidence:** orders run from 1-Apr-2024 to 20-Sep-2026, which is FY 24-25, FY 25-26 and a partial FY 26-27.
- **Decision:** the date table covers complete Indian FYs (April–March), including months with no data yet.
- **Why:** DAX time intelligence (YTD, same period last year) needs whole years.

### D-15 · Never compare a partial year to a full year
- **Decision:** year comparisons use YTD vs prior-year YTD (e.g. Apr–Sep 2026 vs Apr–Sep 2025), and the partial year is labelled on charts.
- **Why:** FY 26-27 total vs FY 25-26 total looks like a collapse, but it's 5.7 months against 12.

### D-16 · Median for "typical", mean for totals
- **Evidence:** order quantity median 27,000, mean 36,789, max 3,93,500 (right-skewed).
- **Decision:** "typical job size" uses the median. Anything that must add back to a total (capacity, cost) uses the mean.
- **Why:** mean × number of jobs = the total; median × number of jobs doesn't.

---

## Phase 2 — Power Query

### D-17 · Access queries and combine queries are kept apart
- **Decision:** a query either reads one source (plus parameters and pure functions) or combines other queries, never both.
- **Why:** this is what stops the formula firewall ("Formula.Firewall: query references other queries") and keeps privacy levels simple.

### D-18 · Every data fix is a function or a reference file, and every fix has a check
- **Decision:** job-number formats, MES v1/v2 schemas, header rows, effective-dated prices and orphan counts are functions (`fn…`). Business lists (legacy customer codes, ink spellings, cost elements, segments) are CSVs in `reference/`, versioned in Git. Each fix has a row in a `val_` query that must return 0.
- **Why:** rules that are code or files can be reviewed and re-run. A manual edit can't.

### D-19 · MES segments are de-duplicated on log_id, ink issues are not
- **Evidence:** 216 re-sent MES segments are byte-identical copies with the same log_id. Identical ink rows have no key, and the number of CMYK rows per job and day equals the SKU's CMYK colour count.
- **Decision:** `Table.Distinct` on log_id for the MES; ink rows kept as they are.
- **Why:** a duplicate is defined by its key. Without a key, identical rows can be genuine (one issue per colour).

### D-20 · Folder-gluer quantities are flagged, not converted
- **Decision:** `qty_unit` = cartons for FG01, FG02 and WP01, sheets elsewhere. Quantities are never added across units.
- **Why:** converting cartons to sheets needs ups per SKU and invents precision. A flag is honest and enough for yield.

### D-21 · Costs are resolved at row level in Power Query
- **Decision:** each issue, plate batch, log segment and rework event gets its effective price in Power Query (`fnAddEffectiveValue`), not in DAX.
- **Why:** the price is a fact about the row on its date. Doing it once at refresh is simpler and faster than an as-of lookup in every measure.

### D-22 · Inferred quote links stay visible
- **Decision:** 406 repeat jobs with no quote_id get the latest Won quote for the same SKU on or before the order date (README rule). `quote_link` = Keyed / Inferred and is a column on Dim Job.
- **Why:** inferred data must be labelled so a reader can exclude it. Inferred jobs' margins match keyed ones (10.7% vs 9.8%), so the inference does not bias the findings.

---

## Phase 3 — Data model

### D-23 · Central fact at job x P&L line
- **Decision:** `Fact Job PL` has one row per job and P&L line (revenue, credit notes, 8 cost elements) with `est_inr` and `actual_inr`.
- **Why:** slicing by cost element never breaks margin %, and the margin bridge is a sum over lines, so it closes by construction (Bridge Check = 0).
- **Trade-off:** the plan's "flexed estimate" (estimate at the actual quantity) was left out; the policy estimate is scaled to the ordered quantity already.

### D-24 · Estimates and actuals are stacked, not full-outer-joined
- **Decision:** estimate lines and actual lines are combined and then grouped by job and element.
- **Why:** a full outer join in M needs key coalescing on both sides; stacking keeps lines that exist on one side only (for example a die on a repeat job's quote but not in its actuals) with less code.

### D-25 · Every fact carries customer_code; Dim Job is not linked to Dim Customer
- **Decision:** star schema. Facts link directly to Dim Customer, Dim Job, Dim Estimator, Dim Machine, Dim Date.
- **Why:** linking Dim Job to Dim Customer as well would give two filter paths from customer to the fact, and Power BI would deactivate one. The one snowflake is Dim Segment → Dim Customer, because Fact Budget is at segment grain and must share the segment list with customers.

### D-26 · Invoice date is the active date; order date is inactive
- **Decision:** `Fact Job PL[invoice_date]` is active; `[order_date]` is an inactive relationship for USERELATIONSHIP.
- **Why:** finance recognises revenue on the invoice date.

### D-27 · Receipts are summed to invoice grain before joining
- **Decision:** `Fact Invoice Payment` takes the last receipt date per invoice.
- **Why:** some invoices are paid in two parts; joining receipts directly would double those invoices (fan-out).

### D-28 · The data-quality checks are loaded into the model
- **Decision:** all `val_` queries are combined into `DQ Checks` (area, check, failures) and shown on the data-quality page.
- **Why:** the report proves its own inputs. A reviewer sees 55 of 55 checks pass without opening Power Query.

---

## Phase 4 — DAX

### D-29 · Indian units by division, not by format string
- **Decision:** card measures such as `Net Revenue (₹ Cr)` divide by 1e7 (crore) or 1e5 (lakh). Base measures keep full rupees with en-IN digit grouping.
- **Why:** format strings can only scale by thousands (each comma divides by 1,000), so lakh and crore can't be done with a dynamic format string.

### D-30 · Time intelligence stops at the data cut-off
- **Decision:** the calculation group's FYTD, PY FYTD and YoY limit the year-to-date window to dates with data (`Is Data Period`), and Budget measures do the same.
- **Why:** FY26-27 has data only to September. Comparing it with all of FY25-26 would look like a collapse (D-15).

### D-31 · New-business win rate excludes re-quotes
- **Evidence:** every revision-1 quote (3,259) is Won; they are re-prices of repeat orders.
- **Decision:** `New-Business Win Rate` uses revision-0 quotes only (16.6% vs the headline 60.3%).
- **Why:** the headline rate measures loyalty, not price competitiveness.

### D-32 · Margin bridge as one measure over the P&L line dimension
- **Decision:** `Margin Bridge` returns the quoted margin on a "Start" line, then actual − estimate for revenue lines and estimate − actual for cost lines. `Bridge Check` proves the steps add up to the actual margin.

---

## Phase 6 — Prove it

### D-33 · Independent replica for reconciliation
- **Decision:** the costing policy was also implemented in T-SQL, separately from Power Query, and the model's totals were compared with it (`tests/control_totals.dax`).
- **Result:** net revenue, gross revenue, credit notes and actual cost match to the rupee; estimated cost differs by Rs 154 on Rs 108.5 Cr (rounding of the 8 estimate elements, D-11).

### D-34 · RLS by sales-rep e-mail; no OLS
- **Decision:** role `Sales Rep` filters Dim Customer on `USERPRINCIPALNAME()`. OLS on cost columns was not added.
- **Why:** every margin measure reads cost columns, so hiding them with OLS would break the measures a sales rep needs. Hiding cost is a report-design decision, not a security one, in this model.

### D-35 · Project rules enforced by CI
- **Decision:** `tests/bpa_rules.json` (descriptions, display folders, DIVIDE, hidden keys, single-direction one-to-many, marked date table, no implicit measures) runs in GitHub Actions on every model change.
