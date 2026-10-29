-- =============================================================================
-- File    : 04_reconciliation.sql
-- Purpose : CONTROL TOTALS, computed independently in SQL from the typed layer,
--           following the README costing policy. Every Power BI number on the
--           revenue / credit-note / quote side must later tie to these totals.
--           If Power BI and this script disagree, trace the cause; never
--           "adjust" a measure to force a match.
-- Scope   : what lives in Postgres only (invoices, credit notes, receipts, FX,
--           quotes, estimates). Actual COSTS come from files (MES, stores, QA)
--           and are reconciled in Power Query's 05 Validation group + Phase 6.
-- Levels  : grand total, FY, currency: levels the Power Query cleaning cannot
--           change. Customer totals WILL differ after the GSTIN/mapping merge;
--           cleaning moves rupees between customers, it never creates them.
-- Output  : Part A  revenue control totals by FY (+ grand total)
--           Part B  revenue by FY x currency (shows the FX conversion)
--           Part C  invoiced vs received -> receivable (fan-out-safe)
--           Part D  promise side: quoted revenue and estimated cost of jobs
--           Part E  tie-out scorecard: every FAIL check must return 0
-- Run     : in psql, connected to conquer:
--           \i 'C:/Users/gunas/Downloads/proj/margin-leakage-intelligence/sql/04_reconciliation.sql'
-- Read-only: creates nothing, changes nothing. Safe to rerun.
-- =============================================================================

\set ON_ERROR_STOP on
\pset footer off

-- -----------------------------------------------------------------------------
-- Building blocks (repeated in each part as CTEs so every part runs alone)
--   FY label : a date minus 3 months lands in the FY's START year.
--              04-Apr-2024 - 3 months = 04-Jan-2024 -> 2024 -> 'FY24-25'
--              31-Mar-2025 - 3 months = 31-Dec-2024 -> 2024 -> 'FY24-25'
--   FX rule  : README rule 4: rate on the document date, or the last rate
--              BEFORE it (weekends / holidays). Done with LEFT JOIN LATERAL ...
--              ORDER BY rate_date DESC LIMIT 1: one rate per row, so it can
--              never fan out, and a missing rate shows as NULL (counted in E).
-- -----------------------------------------------------------------------------


-- =============================================================================
-- PART A: Revenue control totals by FY
--   Gross revenue = qty x rate_per_1000 / 1000, in Rs at invoice-date FX (rule 3)
--   Credit notes  = in Rs at CN-date FX, counted in the FY of the CN DATE
--   Net revenue   = gross - credit notes          (GST is NOT revenue)
-- =============================================================================
\echo ''
\echo '== PART A: Revenue control totals by FY (Rs) =='

WITH inv AS (                                        -- 1 row per invoice, in Rs
    SELECT
        i.invoice_no,
        'FY' || to_char(i.invoice_date - INTERVAL '3 months', 'YY') || '-'
             || to_char(i.invoice_date + INTERVAL '9 months', 'YY')   AS fy,
        i.currency,
        CASE WHEN i.currency = 'INR' THEN 1 ELSE fx.inr_per_unit END  AS fx_rate,
        i.qty * i.rate_per_1000 / 1000                                AS revenue_doc,
        i.gst_18pct                                                   AS gst_doc
    FROM finance.sales_invoices i
    LEFT JOIN LATERAL (
        SELECT f.inr_per_unit
        FROM finance.fx_rates_usd_inr f
        WHERE f.currency  = i.currency
          AND f.rate_date <= i.invoice_date
        ORDER BY f.rate_date DESC
        LIMIT 1
    ) fx ON true
),
inv_fy AS (                                          -- aggregate invoices to FY
    SELECT fy,
           COUNT(*)                                       AS invoices,
           COUNT(*) FILTER (WHERE currency = 'USD')       AS usd_invoices,
           SUM(revenue_doc * fx_rate)                     AS gross_revenue,
           SUM(gst_doc * fx_rate)                         AS gst_collected
    FROM inv
    GROUP BY fy
),
cn AS (                                              -- 1 row per credit note, in Rs
    SELECT
        'FY' || to_char(c.cn_date - INTERVAL '3 months', 'YY') || '-'
             || to_char(c.cn_date + INTERVAL '9 months', 'YY')        AS fy,
        c.amount * CASE WHEN c.currency = 'INR' THEN 1
                        ELSE fx.inr_per_unit END                      AS cn_inr
    FROM finance.credit_notes c
    LEFT JOIN LATERAL (
        SELECT f.inr_per_unit
        FROM finance.fx_rates_usd_inr f
        WHERE f.currency  = c.currency
          AND f.rate_date <= c.cn_date                -- CN's OWN date, not the invoice's
        ORDER BY f.rate_date DESC
        LIMIT 1
    ) fx ON true
),
cn_fy AS (                                           -- aggregate CNs to FY BEFORE joining
    SELECT fy, COUNT(*) AS credit_notes, SUM(cn_inr) AS cn_value
    FROM cn
    GROUP BY fy
),
by_fy AS (                                           -- both sides are 1 row per FY: no fan-out
    SELECT COALESCE(i.fy, c.fy)                 AS fy,
           COALESCE(i.invoices, 0)              AS invoices,
           COALESCE(i.usd_invoices, 0)          AS usd_invoices,
           COALESCE(i.gross_revenue, 0)         AS gross_revenue,
           COALESCE(c.credit_notes, 0)          AS credit_notes,
           COALESCE(c.cn_value, 0)              AS cn_value,
           COALESCE(i.gst_collected, 0)         AS gst_collected
    FROM inv_fy i
    FULL JOIN cn_fy c ON c.fy = i.fy                 -- FULL: keep a FY that has only CNs
)
SELECT COALESCE(fy, 'TOTAL')                      AS fy,
       SUM(invoices)                              AS invoices,       -- = jobs (1 invoice per job)
       SUM(usd_invoices)                          AS usd_invoices,
       ROUND(SUM(gross_revenue), 2)               AS gross_revenue,
       SUM(credit_notes)                          AS credit_notes,
       ROUND(SUM(cn_value), 2)                    AS credit_note_value,
       ROUND(SUM(gross_revenue - cn_value), 2)    AS net_revenue,     -- the page-1 headline
       ROUND(SUM(gst_collected), 2)               AS gst_not_revenue  -- must NOT appear in revenue
FROM by_fy
GROUP BY ROLLUP (fy)                                 -- ROLLUP adds the grand-total row (fy = NULL)
ORDER BY fy NULLS LAST;


-- =============================================================================
-- PART B: Gross revenue by FY x currency
--   Shows the conversion: document-currency amount -> Rs.
--   Effective rate = Rs / USD; it should sit inside the FX file's range for that FY.
-- =============================================================================
\echo ''
\echo '== PART B: Gross revenue by FY x currency =='

WITH inv AS (
    SELECT
        'FY' || to_char(i.invoice_date - INTERVAL '3 months', 'YY') || '-'
             || to_char(i.invoice_date + INTERVAL '9 months', 'YY')   AS fy,
        i.currency,
        i.qty * i.rate_per_1000 / 1000                                AS revenue_doc,
        CASE WHEN i.currency = 'INR' THEN 1 ELSE fx.inr_per_unit END  AS fx_rate
    FROM finance.sales_invoices i
    LEFT JOIN LATERAL (
        SELECT f.inr_per_unit
        FROM finance.fx_rates_usd_inr f
        WHERE f.currency = i.currency AND f.rate_date <= i.invoice_date
        ORDER BY f.rate_date DESC
        LIMIT 1
    ) fx ON true
)
SELECT fy,
       currency,
       COUNT(*)                                               AS invoices,
       ROUND(SUM(revenue_doc), 2)                             AS revenue_in_doc_currency,
       ROUND(SUM(revenue_doc * fx_rate), 2)                   AS revenue_inr,
       ROUND(SUM(revenue_doc * fx_rate) / SUM(revenue_doc), 4) AS effective_rate
FROM inv
GROUP BY fy, currency
ORDER BY fy, currency;


-- =============================================================================
-- PART C: Invoiced vs received -> receivable, by FY x currency
--   Kept in DOCUMENT currency on purpose: receipts include GST and a USD
--   receipt converted at its own date would mix in FX gain/loss. Cash is not
--   revenue; this part exists to prove the receipts join does not fan out.
--   Receipts are SUMMED PER INVOICE FIRST (some invoices are paid in 2 parts).
-- =============================================================================
\echo ''
\echo '== PART C: Invoiced (incl. GST) vs received, document currency =='

WITH rcpt AS (                                       -- 1 row per invoice: fan-out impossible
    SELECT invoice_no, SUM(amount) AS received, COUNT(*) AS receipts
    FROM finance.customer_receipts
    GROUP BY invoice_no
)
SELECT
    'FY' || to_char(i.invoice_date - INTERVAL '3 months', 'YY') || '-'
         || to_char(i.invoice_date + INTERVAL '9 months', 'YY')  AS fy,
    i.currency,
    COUNT(*)                                            AS invoices,
    COUNT(*) FILTER (WHERE r.invoice_no IS NULL)        AS unpaid_invoices,
    COUNT(*) FILTER (WHERE r.receipts > 1)              AS paid_in_parts,
    ROUND(SUM(i.invoice_total), 2)                      AS invoiced_incl_gst,
    ROUND(SUM(COALESCE(r.received, 0)), 2)              AS received,
    ROUND(SUM(i.invoice_total - COALESCE(r.received, 0)), 2) AS receivable
FROM finance.sales_invoices i
LEFT JOIN rcpt r ON r.invoice_no = i.invoice_no      -- LEFT: unpaid invoices stay in
GROUP BY 1, i.currency
ORDER BY 1, i.currency;


-- =============================================================================
-- PART D: Promise side: quoted revenue and estimated cost of jobs, by FY
--   README rule 1: est cost of a job = quote est_total_cost x (order_qty / quote quantity)
--   README rule 2: quoted revenue    = quote quoted_value x same ratio, USD at QUOTE-date FX
--   est_total_cost is already in Rs for every quote (incl. USD quotes) and
--   already includes the 4.5% overhead.
--   FY = FY of the job's INVOICE date (invoice date is the model's active date).
--   Only jobs whose quote_id is filled are linked here. Jobs with a blank
--   quote_id need the Phase 2 quote-link inference (flagged); they are counted
--   separately so the gap is visible, not hidden.
-- =============================================================================
\echo ''
\echo '== PART D: Quoted revenue and estimated cost (jobs linked by quote_id) =='

WITH job_q AS (
    SELECT
        'FY' || to_char(i.invoice_date - INTERVAL '3 months', 'YY') || '-'
             || to_char(i.invoice_date + INTERVAL '9 months', 'YY')  AS fy,
        j.job_no,
        j.quote_id,
        j.order_qty::numeric / q.quantity                            AS qty_ratio,
        q.quoted_value
          * CASE WHEN q.currency = 'INR' THEN 1 ELSE fx.inr_per_unit END AS quoted_value_inr,
        e.est_total_cost
    FROM erp.jobs j
    JOIN finance.sales_invoices i ON i.job_no   = j.job_no     -- 1:1 (checked in Part E)
    LEFT JOIN erp.quotes          q ON q.quote_id = j.quote_id
    LEFT JOIN erp.quote_estimates e ON e.quote_id = j.quote_id
    LEFT JOIN LATERAL (
        SELECT f.inr_per_unit
        FROM finance.fx_rates_usd_inr f
        WHERE f.currency = q.currency AND f.rate_date <= q.quote_date
        ORDER BY f.rate_date DESC
        LIMIT 1
    ) fx ON true
)
SELECT COALESCE(fy, 'TOTAL')                                       AS fy,
       COUNT(*)                                                    AS jobs,
       COUNT(*) FILTER (WHERE quote_id IS NULL)                    AS jobs_without_quote_id,
       ROUND(SUM(quoted_value_inr * qty_ratio), 2)                 AS quoted_revenue_linked,
       ROUND(SUM(est_total_cost   * qty_ratio), 2)                 AS est_cost_linked,
       ROUND(1 - SUM(est_total_cost * qty_ratio)
                 / NULLIF(SUM(quoted_value_inr * qty_ratio), 0), 4) AS quoted_margin_linked
FROM job_q
GROUP BY ROLLUP (fy)
ORDER BY fy NULLS LAST;


-- =============================================================================
-- PART E: Tie-out scorecard
--   Same brick as 03_profiling: COUNT the rows that BREAK the rule.
--   FAIL checks must return 0. INFO checks are facts to explain, not errors.
-- =============================================================================
\echo ''
\echo '== PART E: Tie-out scorecard (FAIL checks must be 0) =='

WITH
inv AS (
    SELECT i.*,
           CASE WHEN i.currency = 'INR' THEN 1 ELSE fx.inr_per_unit END AS fx_rate
    FROM finance.sales_invoices i
    LEFT JOIN LATERAL (
        SELECT f.inr_per_unit FROM finance.fx_rates_usd_inr f
        WHERE f.currency = i.currency AND f.rate_date <= i.invoice_date
        ORDER BY f.rate_date DESC LIMIT 1
    ) fx ON true
),
cn AS (
    SELECT c.*,
           CASE WHEN c.currency = 'INR' THEN 1 ELSE fx.inr_per_unit END AS fx_rate
    FROM finance.credit_notes c
    LEFT JOIN LATERAL (
        SELECT f.inr_per_unit FROM finance.fx_rates_usd_inr f
        WHERE f.currency = c.currency AND f.rate_date <= c.cn_date
        ORDER BY f.rate_date DESC LIMIT 1
    ) fx ON true
),
rcpt AS (
    SELECT invoice_no, SUM(amount) AS received
    FROM finance.customer_receipts
    GROUP BY invoice_no
),
fy_rev AS (                                          -- revenue summed FY by FY ...
    SELECT SUM(fy_total) AS total FROM (
        SELECT SUM(qty * rate_per_1000 / 1000 * fx_rate) AS fy_total
        FROM inv
        GROUP BY to_char(invoice_date - INTERVAL '3 months', 'YYYY')
    ) x
),
cust_rev AS (                                        -- ... and customer by customer
    SELECT SUM(c_total) AS total FROM (
        SELECT SUM(qty * rate_per_1000 / 1000 * fx_rate) AS c_total
        FROM inv
        GROUP BY customer_code
    ) x
),
checks (check_no, area, check_name, broken_rows, severity) AS (
              SELECT 1, 'fx', 'invoices with no Rs value (FX rate not found)',
                     (SELECT COUNT(*) FROM inv WHERE fx_rate IS NULL), 'FAIL'
    UNION ALL SELECT 2, 'fx', 'credit notes with no Rs value (FX rate not found)',
                     (SELECT COUNT(*) FROM cn WHERE fx_rate IS NULL), 'FAIL'
    UNION ALL SELECT 3, 'revenue', 'qty x rate / 1000 differs from taxable_value by > 0.01',
                     (SELECT COUNT(*) FROM inv
                      WHERE ABS(qty * rate_per_1000 / 1000 - taxable_value) > 0.01), 'FAIL'
    UNION ALL SELECT 4, 'gst', 'INR invoice GST <> 18% of taxable (> 0.01)',
                     (SELECT COUNT(*) FROM inv WHERE currency = 'INR'
                        AND ABS(gst_18pct - ROUND(taxable_value * 0.18, 2)) > 0.01), 'FAIL'
    UNION ALL SELECT 5, 'gst', 'USD (export) invoice with non-zero GST',
                     (SELECT COUNT(*) FROM inv WHERE currency = 'USD' AND gst_18pct <> 0), 'FAIL'
    UNION ALL SELECT 6, 'gst', 'invoice_total <> taxable + GST (> 0.01)',
                     (SELECT COUNT(*) FROM inv
                      WHERE ABS(invoice_total - taxable_value - gst_18pct) > 0.01), 'FAIL'
    UNION ALL SELECT 7, 'grain', 'jobs with more than one invoice',
                     (SELECT COUNT(*) FROM (SELECT job_no FROM inv GROUP BY job_no
                                            HAVING COUNT(*) > 1) d), 'FAIL'
    UNION ALL SELECT 8, 'grain', 'invoices whose job is missing from erp.jobs',
                     (SELECT COUNT(*) FROM inv i
                      LEFT JOIN erp.jobs j ON j.job_no = i.job_no
                      WHERE j.job_no IS NULL), 'FAIL'
    UNION ALL SELECT 9, 'grain', 'jobs with no invoice',
                     (SELECT COUNT(*) FROM erp.jobs j
                      LEFT JOIN inv i ON i.job_no = j.job_no
                      WHERE i.job_no IS NULL), 'FAIL'
    UNION ALL SELECT 10, 'credit', 'credit notes whose invoice does not exist',
                     (SELECT COUNT(*) FROM cn c
                      LEFT JOIN inv i ON i.invoice_no = c.invoice_no
                      WHERE i.invoice_no IS NULL), 'FAIL'
    UNION ALL SELECT 11, 'credit', 'credit note bigger than its invoice taxable value',
                     (SELECT COUNT(*) FROM cn c
                      JOIN inv i ON i.invoice_no = c.invoice_no
                      WHERE c.amount > i.taxable_value), 'FAIL'
    UNION ALL SELECT 12, 'credit', 'credit note currency <> its invoice currency',
                     (SELECT COUNT(*) FROM cn c
                      JOIN inv i ON i.invoice_no = c.invoice_no
                      WHERE c.currency <> i.currency), 'FAIL'
    UNION ALL SELECT 13, 'fanout', 'rows after receipts join minus invoice count',
                     (SELECT COUNT(*) FROM inv i LEFT JOIN rcpt r ON r.invoice_no = i.invoice_no)
                     - (SELECT COUNT(*) FROM inv), 'FAIL'
    UNION ALL SELECT 14, 'fanout', 'receipts whose invoice does not exist',
                     (SELECT COUNT(*) FROM finance.customer_receipts r
                      LEFT JOIN inv i ON i.invoice_no = r.invoice_no
                      WHERE i.invoice_no IS NULL), 'FAIL'
    UNION ALL SELECT 15, 'tie-out', 'Rs: sum of FY totals minus grand total (rounded)',
                     (SELECT ROUND((SELECT total FROM fy_rev)
                                 - SUM(qty * rate_per_1000 / 1000 * fx_rate), 2)::bigint FROM inv), 'FAIL'
    UNION ALL SELECT 16, 'tie-out', 'Rs: sum of customer totals minus grand total (rounded)',
                     (SELECT ROUND((SELECT total FROM cust_rev)
                                 - SUM(qty * rate_per_1000 / 1000 * fx_rate), 2)::bigint FROM inv), 'FAIL'
    UNION ALL SELECT 17, 'quote', 'jobs whose quote_id is not found in erp.quotes',
                     (SELECT COUNT(*) FROM erp.jobs j
                      LEFT JOIN erp.quotes q ON q.quote_id = j.quote_id
                      WHERE j.quote_id IS NOT NULL AND q.quote_id IS NULL), 'FAIL'
    UNION ALL SELECT 18, 'quote', 'jobs with a blank quote_id (Phase 2: quote-link inference)',
                     (SELECT COUNT(*) FROM erp.jobs WHERE quote_id IS NULL), 'INFO'
    UNION ALL SELECT 19, 'fx', 'USD invoices dated on a day with no FX row (filled forward)',
                     (SELECT COUNT(*) FROM inv i
                      LEFT JOIN finance.fx_rates_usd_inr f ON f.rate_date = i.invoice_date
                                                          AND f.currency  = i.currency
                      WHERE i.currency = 'USD' AND f.rate_date IS NULL), 'INFO'
    UNION ALL SELECT 20, 'cash', 'unpaid invoices (no receipt yet)',
                     (SELECT COUNT(*) FROM inv i LEFT JOIN rcpt r ON r.invoice_no = i.invoice_no
                      WHERE r.invoice_no IS NULL), 'INFO'
    UNION ALL SELECT 21, 'cash', 'invoices received MORE than invoice total (> Rs 1)',
                     -- tolerance Rs 1, not 0.01: 2-part payments each round to paise, so
                     -- their sum can be a paisa over. Tolerance matches the rounding.
                     (SELECT COUNT(*) FROM inv i JOIN rcpt r ON r.invoice_no = i.invoice_no
                      WHERE r.received > i.invoice_total + 1), 'FAIL'
)
SELECT check_no,
       area,
       check_name,
       broken_rows,
       CASE WHEN severity = 'INFO'  THEN 'INFO'
            WHEN broken_rows = 0    THEN 'PASS'
            ELSE 'FAIL' END                       AS result
FROM checks
ORDER BY CASE WHEN severity = 'FAIL' AND broken_rows <> 0 THEN 0 ELSE 1 END,  -- FAILs first
         check_no;
