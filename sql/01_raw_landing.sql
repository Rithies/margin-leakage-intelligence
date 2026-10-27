-- 01_raw_landing.sql
-- Purpose : land the ERP, finance and master CSVs into schema raw EXACTLY as they are.
--           Every column is TEXT, with no keys and no constraints, so no row can be rejected.
--           Typing, keys and cleaning happen later (02_typed_layer.sql, then Power Query).
-- Scope   : ERP + finance + masters only. MES logs, stores, QA and the Excel files
--           (budget, rate card) stay as files and are read directly by Power Query.
-- Run     : in psql, connected to conquer:
--           \i 'C:/Users/gunas/Downloads/proj/margin-leakage-intelligence/sql/01_raw_landing.sql'
-- Re-runnable: each table is dropped and recreated (idempotent).
-- Note    : \copy is a psql command -> one line, no semicolon, forward slashes in paths.


-- ======================================================================
-- ERP (sales & planning)
-- ======================================================================

DROP TABLE IF EXISTS raw.jobs;
CREATE TABLE raw.jobs (
    job_no          TEXT,
    order_date      TEXT,
    customer_code   TEXT,
    sku_code        TEXT,
    quote_id        TEXT,
    po_number       TEXT,
    order_qty       TEXT,
    due_date        TEXT,
    completed_on    TEXT,
    rush_order      TEXT,
    repeat_order    TEXT,
    artwork_revised TEXT
);
\copy raw.jobs FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/erp/jobs.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.quotes;
CREATE TABLE raw.quotes (
    quote_id          TEXT,
    quote_date        TEXT,
    customer_code     TEXT,
    sku_code          TEXT,
    estimator_code    TEXT,
    quantity          TEXT,
    status            TEXT,
    currency          TEXT,
    valid_days        TEXT,
    revision          TEXT,
    planned_press     TEXT,
    target_margin_pct TEXT,
    price_per_1000    TEXT,
    quoted_value      TEXT
);
\copy raw.quotes FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/erp/quotes.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.quote_estimates;
CREATE TABLE raw.quote_estimates (
    quote_id               TEXT,
    est_gross_sheets       TEXT,
    est_board_kg           TEXT,
    est_board_price_per_kg TEXT,
    est_board_cost         TEXT,
    est_ink_cost           TEXT,
    est_plates             TEXT,
    est_plate_cost         TEXT,
    est_die_cost           TEXT,
    est_press_mr_hrs       TEXT,
    est_press_run_hrs      TEXT,
    est_conversion_cost    TEXT,
    est_freight_cost       TEXT,
    est_rework_allowance   TEXT,
    est_overhead           TEXT,
    est_total_cost         TEXT
);
\copy raw.quote_estimates FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/erp/quote_estimates.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.quote_machine_hours;
CREATE TABLE raw.quote_machine_hours (
    quote_id     TEXT,
    machine_code TEXT,
    est_hours    TEXT
);
\copy raw.quote_machine_hours FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/erp/quote_machine_hours.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.dispatches;
CREATE TABLE raw.dispatches (
    dispatch_no      TEXT,
    job_no           TEXT,
    dispatch_date    TEXT,
    cartons          TEXT,
    drops            TEXT,
    weight_kg        TEXT,
    vehicle_type     TEXT,
    freight_cost_inr TEXT
);
\copy raw.dispatches FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/erp/dispatches.csv' WITH (FORMAT csv, HEADER true)

-- ======================================================================
-- FINANCE (accounts)
-- ======================================================================

DROP TABLE IF EXISTS raw.sales_invoices;
CREATE TABLE raw.sales_invoices (
    invoice_no    TEXT,
    invoice_date  TEXT,
    customer_code TEXT,
    job_no        TEXT,
    qty           TEXT,
    rate_per_1000 TEXT,
    currency      TEXT,
    taxable_value TEXT,
    gst_18pct     TEXT,
    invoice_total TEXT
);
-- Finance exports one file per financial year; all three land in ONE table.
-- invoice_no already carries the FY (SCI/2425/...), so nothing is lost by stacking them.
\copy raw.sales_invoices FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/finance/sales_invoices_FY2425.csv' WITH (FORMAT csv, HEADER true)
\copy raw.sales_invoices FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/finance/sales_invoices_FY2526.csv' WITH (FORMAT csv, HEADER true)
\copy raw.sales_invoices FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/finance/sales_invoices_FY2627.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.credit_notes;
CREATE TABLE raw.credit_notes (
    credit_note_no TEXT,
    cn_date        TEXT,
    invoice_no     TEXT,
    customer_code  TEXT,
    amount         TEXT,
    currency       TEXT,
    reason         TEXT
);
\copy raw.credit_notes FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/finance/credit_notes.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.customer_receipts;
CREATE TABLE raw.customer_receipts (
    receipt_no   TEXT,
    invoice_no   TEXT,
    receipt_date TEXT,
    amount       TEXT,
    currency     TEXT
);
\copy raw.customer_receipts FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/finance/customer_receipts.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.fx_rates_usd_inr;
CREATE TABLE raw.fx_rates_usd_inr (
    rate_date    TEXT,
    currency     TEXT,
    inr_per_unit TEXT
);
\copy raw.fx_rates_usd_inr FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/finance/fx_rates_usd_inr.csv' WITH (FORMAT csv, HEADER true)

-- ======================================================================
-- MASTERS (reference data)
-- ======================================================================

DROP TABLE IF EXISTS raw.customers;
CREATE TABLE raw.customers (
    customer_code      TEXT,
    customer_name      TEXT,
    segment            TEXT,
    city               TEXT,
    state              TEXT,
    country            TEXT,
    gstin              TEXT,
    sales_rep_code     TEXT,
    key_account        TEXT,
    payment_terms_days TEXT,
    billing_currency   TEXT,
    onboarded_on       TEXT
);
\copy raw.customers FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/masters/customers.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.skus;
CREATE TABLE raw.skus (
    sku_code      TEXT,
    customer_code TEXT,
    description   TEXT,
    carton_style  TEXT,
    length_mm     TEXT,
    width_mm      TEXT,
    height_mm     TEXT,
    blank_w_mm    TEXT,
    blank_h_mm    TEXT,
    board_grade   TEXT,
    gsm           TEXT,
    sheet_format  TEXT,
    sheet_w_mm    TEXT,
    sheet_h_mm    TEXT,
    ups           TEXT,
    cmyk_colours  TEXT,
    spot_colours  TEXT,
    metallic      TEXT,
    total_colours TEXT,
    coating       TEXT,
    lamination    TEXT,
    hot_foil      TEXT,
    emboss        TEXT,
    window_patch  TEXT,
    braille       TEXT,
    cov_cmyk      TEXT,
    cov_spot      TEXT,
    cov_met       TEXT,
    status        TEXT
);
\copy raw.skus FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/masters/skus.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.sales_reps;
CREATE TABLE raw.sales_reps (
    sales_rep_code TEXT,
    sales_rep_name TEXT,
    region         TEXT,
    email          TEXT
);
\copy raw.sales_reps FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/masters/sales_reps.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.estimators;
CREATE TABLE raw.estimators (
    estimator_code TEXT,
    estimator_name TEXT,
    joined_on      TEXT,
    left_on        TEXT
);
\copy raw.estimators FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/masters/estimators.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.operators;
CREATE TABLE raw.operators (
    operator_code TEXT,
    skill_grade   TEXT,
    home_machine  TEXT
);
\copy raw.operators FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/masters/operators.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.board_grades;
CREATE TABLE raw.board_grades (
    grade_code TEXT,
    grade_name TEXT,
    fibre      TEXT
);
\copy raw.board_grades FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/masters/board_grades.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.board_price_history;
CREATE TABLE raw.board_price_history (
    month            TEXT,
    grade_code       TEXT,
    price_inr_per_kg TEXT
);
\copy raw.board_price_history FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/masters/board_price_history.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.ink_price_list;
CREATE TABLE raw.ink_price_list (
    ink_code          TEXT,
    ink_type          TEXT,
    effective_from    TEXT,
    price_inr_per_kg  TEXT,
    std_gsm_at_100pct TEXT
);
\copy raw.ink_price_list FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/masters/ink_price_list.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.plate_price_list;
CREATE TABLE raw.plate_price_list (
    plate_format        TEXT,
    effective_from      TEXT,
    price_inr_per_plate TEXT
);
\copy raw.plate_price_list FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/masters/plate_price_list.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS raw.rework_reasons;
CREATE TABLE raw.rework_reasons (
    reason_code    TEXT,
    reason         TEXT,
    department     TEXT,
    responsibility TEXT
);
\copy raw.rework_reasons FROM 'C:/Users/gunas/Downloads/proj/Conquer_JobCosting_v2/data/masters/rework_reasons.csv' WITH (FORMAT csv, HEADER true)

-- ======================================================================
-- CHECK: every table's row count must equal the record count of its CSV(s).
-- The 'status' column must say OK on every row. Any MISMATCH = stop and investigate.
-- ======================================================================
WITH expected(table_name, expected_rows) AS (      -- CTE 1: what the files contain
    VALUES
        ('jobs', 7345),
        ('quotes', 6223),
        ('quote_estimates', 6223),
        ('quote_machine_hours', 20481),
        ('dispatches', 7345),
        ('sales_invoices', 7345),
        ('credit_notes', 214),
        ('customer_receipts', 7970),
        ('fx_rates_usd_inr', 718),
        ('customers', 45),
        ('skus', 2967),
        ('sales_reps', 6),
        ('estimators', 4),
        ('operators', 30),
        ('board_grades', 4),
        ('board_price_history', 132),
        ('ink_price_list', 15),
        ('plate_price_list', 6),
        ('rework_reasons', 9)
),
actual(table_name, actual_rows) AS (               -- CTE 2: what actually landed
    SELECT 'jobs', COUNT(*) FROM raw.jobs
    UNION ALL SELECT 'quotes', COUNT(*) FROM raw.quotes
    UNION ALL SELECT 'quote_estimates', COUNT(*) FROM raw.quote_estimates
    UNION ALL SELECT 'quote_machine_hours', COUNT(*) FROM raw.quote_machine_hours
    UNION ALL SELECT 'dispatches', COUNT(*) FROM raw.dispatches
    UNION ALL SELECT 'sales_invoices', COUNT(*) FROM raw.sales_invoices
    UNION ALL SELECT 'credit_notes', COUNT(*) FROM raw.credit_notes
    UNION ALL SELECT 'customer_receipts', COUNT(*) FROM raw.customer_receipts
    UNION ALL SELECT 'fx_rates_usd_inr', COUNT(*) FROM raw.fx_rates_usd_inr
    UNION ALL SELECT 'customers', COUNT(*) FROM raw.customers
    UNION ALL SELECT 'skus', COUNT(*) FROM raw.skus
    UNION ALL SELECT 'sales_reps', COUNT(*) FROM raw.sales_reps
    UNION ALL SELECT 'estimators', COUNT(*) FROM raw.estimators
    UNION ALL SELECT 'operators', COUNT(*) FROM raw.operators
    UNION ALL SELECT 'board_grades', COUNT(*) FROM raw.board_grades
    UNION ALL SELECT 'board_price_history', COUNT(*) FROM raw.board_price_history
    UNION ALL SELECT 'ink_price_list', COUNT(*) FROM raw.ink_price_list
    UNION ALL SELECT 'plate_price_list', COUNT(*) FROM raw.plate_price_list
    UNION ALL SELECT 'rework_reasons', COUNT(*) FROM raw.rework_reasons
)
SELECT e.table_name,
       e.expected_rows,
       a.actual_rows,
       CASE WHEN e.expected_rows = a.actual_rows THEN 'OK' ELSE 'MISMATCH' END AS status
FROM expected e
JOIN actual   a ON a.table_name = e.table_name      -- match the two lists by table name
ORDER BY e.table_name;
