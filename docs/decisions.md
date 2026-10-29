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
