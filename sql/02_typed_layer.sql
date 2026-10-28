-- 02_typed_layer.sql
-- Purpose : build TYPED copies of the raw tables in schemas erp / finance / masters.
--           Rule of this layer: change TYPES, never VALUES.
--             * text dates      -> DATE      (DD-MM-YYYY from ERP/finance, ISO from masters)
--             * text numbers    -> INTEGER for counts, NUMERIC for money / rates / hours
--             * Yes/No, Y/N, 0/1 -> BOOLEAN
--             * empty string    -> NULL      (missing is NULL, not '')
--           No cleaning, de-duplication, code mapping or keys here. Those need profiling first
--           (03_profiling.sql) and the business rules live in Power Query.
-- Fails loudly: every cast is strict. One unparseable value stops the script and NOTHING
--           is changed (single transaction). Silent NULLs are never produced by a bad cast.
-- Run     : in psql, connected to conquer:
--           \i 'C:/Users/gunas/Downloads/proj/margin-leakage-intelligence/sql/02_typed_layer.sql'
-- Re-runnable: drops and rebuilds every typed table.

\set ON_ERROR_STOP on
BEGIN;

-- ======================================================================
-- ERP
-- ======================================================================

DROP TABLE IF EXISTS erp.jobs;
CREATE TABLE erp.jobs AS
SELECT
    job_no,
    to_date(NULLIF(order_date, ''),   'DD-MM-YYYY') AS order_date,
    customer_code,                                   -- old codes (e.g. -OLD) kept as-is; mapped in Power Query
    sku_code,
    NULLIF(quote_id, '')                            AS quote_id,   -- blank = repeat job keyed without a quote
    po_number,
    NULLIF(order_qty, '')::integer                  AS order_qty,
    to_date(NULLIF(due_date, ''),     'DD-MM-YYYY') AS due_date,
    to_date(NULLIF(completed_on, ''), 'DD-MM-YYYY') AS completed_on,
    NULLIF(rush_order, '')::boolean                 AS rush_order,      -- Yes/No
    NULLIF(repeat_order, '')::boolean               AS repeat_order,    -- 1/0
    NULLIF(artwork_revised, '')::boolean            AS artwork_revised  -- 1/0
FROM raw.jobs;
COMMENT ON TABLE erp.jobs IS 'Grain: one production job. Typed copy of raw.jobs.';

DROP TABLE IF EXISTS erp.quotes;
CREATE TABLE erp.quotes AS
SELECT
    quote_id,
    to_date(NULLIF(quote_date, ''), 'DD-MM-YYYY') AS quote_date,
    customer_code,
    sku_code,
    estimator_code,
    NULLIF(quantity, '')::integer           AS quantity,
    status,
    currency,
    NULLIF(valid_days, '')::integer         AS valid_days,
    NULLIF(revision, '')::integer           AS revision,
    planned_press,
    NULLIF(target_margin_pct, '')::numeric  AS target_margin_pct,   -- a fraction: 0.2138 = 21.38%
    NULLIF(price_per_1000, '')::numeric     AS price_per_1000,      -- in the quote's currency
    NULLIF(quoted_value, '')::numeric       AS quoted_value         -- in the quote's currency
FROM raw.quotes;
COMMENT ON TABLE erp.quotes IS 'Grain: one quote (won or lost). Amounts in quote currency.';

DROP TABLE IF EXISTS erp.quote_estimates;
CREATE TABLE erp.quote_estimates AS
SELECT
    quote_id,
    NULLIF(est_gross_sheets, '')::integer        AS est_gross_sheets,
    NULLIF(est_board_kg, '')::numeric            AS est_board_kg,
    NULLIF(est_board_price_per_kg, '')::numeric  AS est_board_price_per_kg,
    NULLIF(est_board_cost, '')::numeric          AS est_board_cost,
    NULLIF(est_ink_cost, '')::numeric            AS est_ink_cost,
    NULLIF(est_plates, '')::integer              AS est_plates,
    NULLIF(est_plate_cost, '')::numeric          AS est_plate_cost,
    NULLIF(est_die_cost, '')::numeric            AS est_die_cost,
    NULLIF(est_press_mr_hrs, '')::numeric        AS est_press_mr_hrs,
    NULLIF(est_press_run_hrs, '')::numeric       AS est_press_run_hrs,
    NULLIF(est_conversion_cost, '')::numeric     AS est_conversion_cost,
    NULLIF(est_freight_cost, '')::numeric        AS est_freight_cost,
    NULLIF(est_rework_allowance, '')::numeric    AS est_rework_allowance,
    NULLIF(est_overhead, '')::numeric            AS est_overhead,
    NULLIF(est_total_cost, '')::numeric          AS est_total_cost
FROM raw.quote_estimates;
COMMENT ON TABLE erp.quote_estimates IS 'Grain: one quote, WIDE (one column per cost element). Unpivoted in Power Query.';

DROP TABLE IF EXISTS erp.quote_machine_hours;
CREATE TABLE erp.quote_machine_hours AS
SELECT
    quote_id,
    machine_code,
    NULLIF(est_hours, '')::numeric AS est_hours
FROM raw.quote_machine_hours;
COMMENT ON TABLE erp.quote_machine_hours IS 'Grain: quote x machine (estimated hours).';

DROP TABLE IF EXISTS erp.dispatches;
CREATE TABLE erp.dispatches AS
SELECT
    dispatch_no,
    job_no,
    to_date(NULLIF(dispatch_date, ''), 'DD-MM-YYYY') AS dispatch_date,
    NULLIF(cartons, '')::integer           AS cartons,
    NULLIF(drops, '')::integer             AS drops,
    NULLIF(weight_kg, '')::numeric         AS weight_kg,
    vehicle_type,
    NULLIF(freight_cost_inr, '')::numeric  AS freight_cost_inr
FROM raw.dispatches;
COMMENT ON TABLE erp.dispatches IS 'Grain: one delivery note.';

-- ======================================================================
-- FINANCE
-- ======================================================================

DROP TABLE IF EXISTS finance.sales_invoices;
CREATE TABLE finance.sales_invoices AS
SELECT
    invoice_no,
    to_date(NULLIF(invoice_date, ''), 'DD-MM-YYYY') AS invoice_date,
    customer_code,
    job_no,
    NULLIF(qty, '')::integer            AS qty,
    NULLIF(rate_per_1000, '')::numeric  AS rate_per_1000,   -- in invoice currency
    currency,
    NULLIF(taxable_value, '')::numeric  AS taxable_value,
    NULLIF(gst_18pct, '')::numeric      AS gst_18pct,       -- GST is NOT revenue
    NULLIF(invoice_total, '')::numeric  AS invoice_total
FROM raw.sales_invoices;
COMMENT ON TABLE finance.sales_invoices IS 'Grain: one invoice (one per job). Three FY files stacked.';

DROP TABLE IF EXISTS finance.credit_notes;
CREATE TABLE finance.credit_notes AS
SELECT
    credit_note_no,
    to_date(NULLIF(cn_date, ''), 'DD-MM-YYYY') AS cn_date,
    invoice_no,
    customer_code,
    NULLIF(amount, '')::numeric AS amount,
    currency,
    reason
FROM raw.credit_notes;
COMMENT ON TABLE finance.credit_notes IS 'Grain: one credit note. Belongs to the job of its invoice.';

DROP TABLE IF EXISTS finance.customer_receipts;
CREATE TABLE finance.customer_receipts AS
SELECT
    receipt_no,
    invoice_no,
    to_date(NULLIF(receipt_date, ''), 'DD-MM-YYYY') AS receipt_date,
    NULLIF(amount, '')::numeric AS amount,
    currency
FROM raw.customer_receipts;
COMMENT ON TABLE finance.customer_receipts IS 'Grain: one receipt (an invoice can be paid in parts).';

DROP TABLE IF EXISTS finance.fx_rates_usd_inr;
CREATE TABLE finance.fx_rates_usd_inr AS
SELECT
    NULLIF(rate_date, '')::date          AS rate_date,      -- ISO yyyy-mm-dd: a plain cast is safe
    currency,
    NULLIF(inr_per_unit, '')::numeric    AS inr_per_unit
FROM raw.fx_rates_usd_inr;
COMMENT ON TABLE finance.fx_rates_usd_inr IS 'Grain: one business day. Gaps (weekends/holidays) are filled forward in Power Query.';

-- ======================================================================
-- MASTERS
-- ======================================================================

DROP TABLE IF EXISTS masters.customers;
CREATE TABLE masters.customers AS
SELECT
    customer_code,
    customer_name,                                   -- NOT trimmed/cased here; that is Power Query's job
    segment,
    city,
    state,
    country,
    NULLIF(gstin, '')                                AS gstin,
    sales_rep_code,
    NULLIF(key_account, '')::boolean                 AS key_account,   -- Y/N
    NULLIF(payment_terms_days, '')::integer          AS payment_terms_days,
    billing_currency,
    to_date(NULLIF(onboarded_on, ''), 'DD-MM-YYYY')  AS onboarded_on
FROM raw.customers;
COMMENT ON TABLE masters.customers IS 'Grain: one customer code (includes legacy codes).';

DROP TABLE IF EXISTS masters.skus;
CREATE TABLE masters.skus AS
SELECT
    sku_code,
    customer_code,
    description,
    carton_style,
    NULLIF(length_mm, '')::integer      AS length_mm,
    NULLIF(width_mm, '')::integer       AS width_mm,
    NULLIF(height_mm, '')::integer      AS height_mm,
    NULLIF(blank_w_mm, '')::integer     AS blank_w_mm,
    NULLIF(blank_h_mm, '')::integer     AS blank_h_mm,
    board_grade,
    NULLIF(gsm, '')::integer            AS gsm,
    sheet_format,                                    -- a CODE (102 / 74), not a quantity: stays TEXT
    NULLIF(sheet_w_mm, '')::integer     AS sheet_w_mm,
    NULLIF(sheet_h_mm, '')::integer     AS sheet_h_mm,
    NULLIF(ups, '')::integer            AS ups,
    NULLIF(cmyk_colours, '')::integer   AS cmyk_colours,
    NULLIF(spot_colours, '')::integer   AS spot_colours,
    NULLIF(metallic, '')::integer       AS metallic,
    NULLIF(total_colours, '')::integer  AS total_colours,
    coating,
    NULLIF(lamination, '')::boolean     AS lamination,
    NULLIF(hot_foil, '')::boolean       AS hot_foil,
    NULLIF(emboss, '')::boolean         AS emboss,
    NULLIF(window_patch, '')::boolean   AS window_patch,
    NULLIF(braille, '')::boolean        AS braille,
    NULLIF(cov_cmyk, '')::numeric       AS cov_cmyk,
    NULLIF(cov_spot, '')::numeric       AS cov_spot,
    NULLIF(cov_met, '')::numeric        AS cov_met,
    status
FROM raw.skus;
COMMENT ON TABLE masters.skus IS 'Grain: one SKU (active or quote-only).';

DROP TABLE IF EXISTS masters.sales_reps;
CREATE TABLE masters.sales_reps AS
SELECT sales_rep_code, sales_rep_name, region, email
FROM raw.sales_reps;

DROP TABLE IF EXISTS masters.estimators;
CREATE TABLE masters.estimators AS
SELECT
    estimator_code,
    estimator_name,
    NULLIF(joined_on, '')::date AS joined_on,        -- ISO
    NULLIF(left_on, '')::date   AS left_on           -- blank = still employed
FROM raw.estimators;

DROP TABLE IF EXISTS masters.operators;
CREATE TABLE masters.operators AS
SELECT operator_code, skill_grade, home_machine
FROM raw.operators;

DROP TABLE IF EXISTS masters.board_grades;
CREATE TABLE masters.board_grades AS
SELECT grade_code, grade_name, fibre
FROM raw.board_grades;

DROP TABLE IF EXISTS masters.board_price_history;
CREATE TABLE masters.board_price_history AS
SELECT
    to_date(NULLIF(month, ''), 'Mon-YYYY')    AS month_start,   -- 'Jan-2024' -> 2024-01-01
    grade_code,
    NULLIF(price_inr_per_kg, '')::numeric     AS price_inr_per_kg
FROM raw.board_price_history;
COMMENT ON TABLE masters.board_price_history IS 'Grain: month x board grade.';

DROP TABLE IF EXISTS masters.ink_price_list;
CREATE TABLE masters.ink_price_list AS
SELECT
    ink_code,
    ink_type,
    NULLIF(effective_from, '')::date            AS effective_from,   -- ISO
    NULLIF(price_inr_per_kg, '')::numeric       AS price_inr_per_kg,
    NULLIF(std_gsm_at_100pct, '')::numeric      AS std_gsm_at_100pct
FROM raw.ink_price_list;
COMMENT ON TABLE masters.ink_price_list IS 'Grain: ink x effective_from (effective-dated price list).';

DROP TABLE IF EXISTS masters.plate_price_list;
CREATE TABLE masters.plate_price_list AS
SELECT
    plate_format,                                    -- CODE, matches skus.sheet_format: TEXT
    NULLIF(effective_from, '')::date            AS effective_from,
    NULLIF(price_inr_per_plate, '')::numeric    AS price_inr_per_plate
FROM raw.plate_price_list;
COMMENT ON TABLE masters.plate_price_list IS 'Grain: plate format x effective_from.';

DROP TABLE IF EXISTS masters.rework_reasons;
CREATE TABLE masters.rework_reasons AS
SELECT reason_code, reason, department, responsibility
FROM raw.rework_reasons;

COMMIT;

-- ======================================================================
-- CHECK: typed row count must equal raw row count for all 19 tables.
-- The typing step must never add or lose rows. Every row must say OK.
-- ======================================================================
WITH counts(table_name, raw_rows, typed_rows) AS (
              SELECT 'jobs',                (SELECT COUNT(*) FROM raw.jobs),                (SELECT COUNT(*) FROM erp.jobs)
    UNION ALL SELECT 'quotes',              (SELECT COUNT(*) FROM raw.quotes),              (SELECT COUNT(*) FROM erp.quotes)
    UNION ALL SELECT 'quote_estimates',     (SELECT COUNT(*) FROM raw.quote_estimates),     (SELECT COUNT(*) FROM erp.quote_estimates)
    UNION ALL SELECT 'quote_machine_hours', (SELECT COUNT(*) FROM raw.quote_machine_hours), (SELECT COUNT(*) FROM erp.quote_machine_hours)
    UNION ALL SELECT 'dispatches',          (SELECT COUNT(*) FROM raw.dispatches),          (SELECT COUNT(*) FROM erp.dispatches)
    UNION ALL SELECT 'sales_invoices',      (SELECT COUNT(*) FROM raw.sales_invoices),      (SELECT COUNT(*) FROM finance.sales_invoices)
    UNION ALL SELECT 'credit_notes',        (SELECT COUNT(*) FROM raw.credit_notes),        (SELECT COUNT(*) FROM finance.credit_notes)
    UNION ALL SELECT 'customer_receipts',   (SELECT COUNT(*) FROM raw.customer_receipts),   (SELECT COUNT(*) FROM finance.customer_receipts)
    UNION ALL SELECT 'fx_rates_usd_inr',    (SELECT COUNT(*) FROM raw.fx_rates_usd_inr),    (SELECT COUNT(*) FROM finance.fx_rates_usd_inr)
    UNION ALL SELECT 'customers',           (SELECT COUNT(*) FROM raw.customers),           (SELECT COUNT(*) FROM masters.customers)
    UNION ALL SELECT 'skus',                (SELECT COUNT(*) FROM raw.skus),                (SELECT COUNT(*) FROM masters.skus)
    UNION ALL SELECT 'sales_reps',          (SELECT COUNT(*) FROM raw.sales_reps),          (SELECT COUNT(*) FROM masters.sales_reps)
    UNION ALL SELECT 'estimators',          (SELECT COUNT(*) FROM raw.estimators),          (SELECT COUNT(*) FROM masters.estimators)
    UNION ALL SELECT 'operators',           (SELECT COUNT(*) FROM raw.operators),           (SELECT COUNT(*) FROM masters.operators)
    UNION ALL SELECT 'board_grades',        (SELECT COUNT(*) FROM raw.board_grades),        (SELECT COUNT(*) FROM masters.board_grades)
    UNION ALL SELECT 'board_price_history', (SELECT COUNT(*) FROM raw.board_price_history), (SELECT COUNT(*) FROM masters.board_price_history)
    UNION ALL SELECT 'ink_price_list',      (SELECT COUNT(*) FROM raw.ink_price_list),      (SELECT COUNT(*) FROM masters.ink_price_list)
    UNION ALL SELECT 'plate_price_list',    (SELECT COUNT(*) FROM raw.plate_price_list),    (SELECT COUNT(*) FROM masters.plate_price_list)
    UNION ALL SELECT 'rework_reasons',      (SELECT COUNT(*) FROM raw.rework_reasons),      (SELECT COUNT(*) FROM masters.rework_reasons)
)
SELECT table_name, raw_rows, typed_rows,
       CASE WHEN raw_rows = typed_rows THEN 'OK' ELSE 'MISMATCH' END AS status
FROM counts
ORDER BY table_name;
