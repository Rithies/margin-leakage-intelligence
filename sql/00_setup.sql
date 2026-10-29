-- =============================================================================
-- File    : 00_setup.sql
-- Purpose : one-time setup so the repo runs on a fresh PostgreSQL install.
--           Creates the four schemas that 01_raw_landing.sql and
--           02_typed_layer.sql write into.
-- Run     : FIRST create the database, connected to the default db:
--               CREATE DATABASE conquer;
--           then connect to it and run this file:
--               \c conquer
--               \i 00_setup.sql
-- Safe to rerun: IF NOT EXISTS skips schemas that already exist.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;       -- landing: CSVs exactly as received (all TEXT)
CREATE SCHEMA IF NOT EXISTS erp;       -- typed ERP tables (jobs, quotes, dispatches...)
CREATE SCHEMA IF NOT EXISTS finance;   -- typed finance tables (invoices, credit notes, receipts, FX)
CREATE SCHEMA IF NOT EXISTS masters;   -- typed master data (customers, SKUs, sales reps...)

-- Check: should list raw, erp, finance, masters
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('raw', 'erp', 'finance', 'masters')
ORDER BY schema_name;
