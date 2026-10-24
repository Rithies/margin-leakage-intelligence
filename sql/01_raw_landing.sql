-- 01_raw_landing.sql
-- Purpose: land source CSVs exactly as they are. All columns TEXT; no keys, no types.
-- Re-runnable: drops and recreates each table.

-- ===== ERP =====
DROP TABLE IF EXISTS raw.jobs;          -- start clean so the script can be rerun
CREATE TABLE raw.jobs (
    job_no          TEXT,               -- column names copied from the CSV header, in the same order
    order_date      TEXT,               -- stays TEXT: '01-04-2024' is DD-MM-YYYY; we convert later
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
-- FORMAT csv: handles quoted values containing commas
-- HEADER true: skip line 1 (the column names)
-- forward slashes in the Windows path avoid backslash-escape trouble
-- \copy is a psql command, so: one line, no semicolon