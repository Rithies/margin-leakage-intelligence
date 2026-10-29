-- =============================================================================
-- File    : 03_profiling.sql
-- Purpose : PROFILE the typed layer before anything is built on it.
--           Answers one question: "can I trust this data, and if not, where
--           exactly is it wrong?"  It only MEASURES. It never changes data.
--           Fixes happen later, in Power Query (Phase 2), as documented rules.
-- Run     : in psql, connected to conquer:
--             \i 'C:/Users/gunas/Downloads/proj/margin-leakage-intelligence/sql/03_profiling.sql'
-- Read-only: safe to rerun at any time.
--
-- Layout
--   PART A  Scorecard  : one row per rule. Every rule is written as
--                        "COUNT the rows that BREAK the rule", so
--                          expect = 'zero' -> 0 = PASS, >0 = FAIL
--                          expect = 'info' -> a number to know, not a rule
--                        A FAIL is a DATA FINDING to explain, not a script bug.
--   PART B  Profiles   : ranges and distributions (what does the data look like?)
--   PART C  Drill-down : list the actual rows behind a failing check
--
-- The five check families
--   1 Volume        how many rows?
--   2 Uniqueness    is the key really unique?            (grain)
--   3 Completeness  NULLs in columns that must be filled
--   4 Integrity     does every foreign key find its parent? (orphans)
--   5 Validity      plausible values, cross-column and cross-table rules
-- =============================================================================


-- =============================================================================
-- PART A  SCORECARD
-- =============================================================================
WITH checks(tbl, family, check_name, failures, expect) AS (

-- ---------------------------------------------------------------- erp.jobs
          SELECT 'jobs', '1 Volume', 'row count',
                 (SELECT COUNT(*) FROM erp.jobs), 'info'
UNION ALL SELECT 'jobs', '2 Uniqueness', 'duplicate job_no',
                 (SELECT COUNT(*) FROM (SELECT job_no FROM erp.jobs
                                        GROUP BY job_no HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'jobs', '3 Completeness', 'NULL in a required column (order_date, customer, sku, qty)',
                 (SELECT COUNT(*) FROM erp.jobs
                  WHERE order_date IS NULL OR customer_code IS NULL
                     OR sku_code IS NULL  OR order_qty IS NULL), 'zero'
UNION ALL SELECT 'jobs', '3 Completeness', 'NULL quote_id (repeat jobs keyed without a quote)',
                 (SELECT COUNT(*) - COUNT(quote_id) FROM erp.jobs), 'info'   -- COUNT(col) skips NULLs
UNION ALL SELECT 'jobs', '3 Completeness', 'NULL completed_on (open jobs)',
                 (SELECT COUNT(*) - COUNT(completed_on) FROM erp.jobs), 'info'
UNION ALL SELECT 'jobs', '4 Integrity', 'customer_code not in customer master',
                 (SELECT COUNT(*) FROM erp.jobs j
                  LEFT JOIN masters.customers c ON c.customer_code = j.customer_code
                  WHERE c.customer_code IS NULL), 'zero'                       -- anti-join
UNION ALL SELECT 'jobs', '4 Integrity', 'sku_code not in SKU master',
                 (SELECT COUNT(*) FROM erp.jobs j
                  LEFT JOIN masters.skus s ON s.sku_code = j.sku_code
                  WHERE s.sku_code IS NULL), 'zero'
UNION ALL SELECT 'jobs', '4 Integrity', 'quote_id given but not in quotes',
                 (SELECT COUNT(*) FROM erp.jobs j
                  LEFT JOIN erp.quotes q ON q.quote_id = j.quote_id
                  WHERE q.quote_id IS NULL
                    AND j.quote_id IS NOT NULL), 'zero'   -- nullable FK: NULL is allowed, not an orphan
UNION ALL SELECT 'jobs', '5 Validity', 'order_qty <= 0',
                 (SELECT COUNT(*) FROM erp.jobs WHERE order_qty <= 0), 'zero'
UNION ALL SELECT 'jobs', '5 Validity', 'due_date before order_date',
                 (SELECT COUNT(*) FROM erp.jobs WHERE due_date < order_date), 'zero'
UNION ALL SELECT 'jobs', '5 Validity', 'completed_on before order_date',
                 (SELECT COUNT(*) FROM erp.jobs WHERE completed_on < order_date), 'zero'  -- NULL < x is UNKNOWN -> open jobs excluded
UNION ALL SELECT 'jobs', '5 Validity', 'FY in job_no <> FY of order_date',
                 (SELECT COUNT(*) FROM erp.jobs
                  WHERE substring(job_no FROM 4 FOR 4)                        -- '2425' from 'JB-2425-00001'
                     <> to_char(order_date - INTERVAL '3 months', 'YY')       -- FY start year (Apr -> Jan)
                     || to_char(order_date + INTERVAL '9 months', 'YY')), 'zero'  -- FY end year
UNION ALL SELECT 'jobs', '5 Validity', 'job customer <> customer that owns the SKU',
                 (SELECT COUNT(*) FROM erp.jobs j
                  JOIN masters.skus s ON s.sku_code = j.sku_code
                  WHERE s.customer_code <> j.customer_code), 'zero'
UNION ALL SELECT 'jobs', '5 Validity', 'job customer/SKU <> its quote customer/SKU',
                 (SELECT COUNT(*) FROM erp.jobs j
                  JOIN erp.quotes q ON q.quote_id = j.quote_id
                  WHERE q.customer_code <> j.customer_code
                     OR q.sku_code      <> j.sku_code), 'zero'
UNION ALL SELECT 'jobs', '5 Validity', 'job linked to a quote that was not Won',
                 (SELECT COUNT(*) FROM erp.jobs j
                  JOIN erp.quotes q ON q.quote_id = j.quote_id
                  WHERE q.status <> 'Won'), 'zero'
UNION ALL SELECT 'jobs', '5 Validity', 'order_date before its quote_date',
                 (SELECT COUNT(*) FROM erp.jobs j
                  JOIN erp.quotes q ON q.quote_id = j.quote_id
                  WHERE j.order_date < q.quote_date), 'zero'

-- ---------------------------------------------------------------- erp.quotes
UNION ALL SELECT 'quotes', '1 Volume', 'row count',
                 (SELECT COUNT(*) FROM erp.quotes), 'info'
UNION ALL SELECT 'quotes', '2 Uniqueness', 'duplicate quote_id',
                 (SELECT COUNT(*) FROM (SELECT quote_id FROM erp.quotes
                                        GROUP BY quote_id HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'quotes', '2 Uniqueness', 'quote Won by more than one job',
                 (SELECT COUNT(*) FROM (SELECT quote_id FROM erp.jobs WHERE quote_id IS NOT NULL
                                        GROUP BY quote_id HAVING COUNT(*) > 1) d), 'info'
UNION ALL SELECT 'quotes', '3 Completeness', 'NULL in a required column',
                 (SELECT COUNT(*) FROM erp.quotes
                  WHERE quote_date IS NULL OR customer_code IS NULL OR sku_code IS NULL
                     OR estimator_code IS NULL OR quantity IS NULL OR quoted_value IS NULL), 'zero'
UNION ALL SELECT 'quotes', '4 Integrity', 'customer_code not in customer master',
                 (SELECT COUNT(*) FROM erp.quotes q
                  LEFT JOIN masters.customers c ON c.customer_code = q.customer_code
                  WHERE c.customer_code IS NULL), 'zero'
UNION ALL SELECT 'quotes', '4 Integrity', 'sku_code not in SKU master',
                 (SELECT COUNT(*) FROM erp.quotes q
                  LEFT JOIN masters.skus s ON s.sku_code = q.sku_code
                  WHERE s.sku_code IS NULL), 'zero'
UNION ALL SELECT 'quotes', '4 Integrity', 'estimator_code not in estimator master',
                 (SELECT COUNT(*) FROM erp.quotes q
                  LEFT JOIN masters.estimators e ON e.estimator_code = q.estimator_code
                  WHERE e.estimator_code IS NULL), 'zero'
UNION ALL SELECT 'quotes', '4 Integrity', 'Won quote with no job (info: may still be open)',
                 (SELECT COUNT(*) FROM erp.quotes q
                  LEFT JOIN erp.jobs j ON j.quote_id = q.quote_id
                  WHERE q.status = 'Won' AND j.job_no IS NULL), 'info'
UNION ALL SELECT 'quotes', '5 Validity', 'quantity or price <= 0',
                 (SELECT COUNT(*) FROM erp.quotes
                  WHERE quantity <= 0 OR price_per_1000 <= 0), 'zero'
UNION ALL SELECT 'quotes', '5 Validity', 'quoted_value <> quantity x price_per_1000 / 1000 (tolerance 1)',
                 (SELECT COUNT(*) FROM erp.quotes
                  WHERE ABS(quoted_value - quantity * price_per_1000 / 1000.0) > 1), 'zero'
UNION ALL SELECT 'quotes', '5 Validity', 'target_margin_pct outside 0..1 (stored as a fraction)',
                 (SELECT COUNT(*) FROM erp.quotes
                  WHERE target_margin_pct < 0 OR target_margin_pct >= 1), 'zero'
UNION ALL SELECT 'quotes', '5 Validity', 'quote dated outside the estimator''s employment',
                 (SELECT COUNT(*) FROM erp.quotes q
                  JOIN masters.estimators e ON e.estimator_code = q.estimator_code
                  WHERE q.quote_date < e.joined_on
                     OR q.quote_date > e.left_on), 'zero'                  -- NULL left_on = still employed -> excluded
UNION ALL SELECT 'quotes', '5 Validity', 'currency not INR/USD',
                 (SELECT COUNT(*) FROM erp.quotes
                  WHERE currency NOT IN ('INR', 'USD') OR currency IS NULL), 'zero'

-- ------------------------------------------------- erp.quote_estimates (wide)
UNION ALL SELECT 'quote_estimates', '2 Uniqueness', 'duplicate quote_id (grain = 1 row per quote)',
                 (SELECT COUNT(*) FROM (SELECT quote_id FROM erp.quote_estimates
                                        GROUP BY quote_id HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'quote_estimates', '4 Integrity', 'quote_id not in quotes',
                 (SELECT COUNT(*) FROM erp.quote_estimates e
                  LEFT JOIN erp.quotes q ON q.quote_id = e.quote_id
                  WHERE q.quote_id IS NULL), 'zero'
UNION ALL SELECT 'quote_estimates', '4 Integrity', 'quote with no estimate row',
                 (SELECT COUNT(*) FROM erp.quotes q
                  LEFT JOIN erp.quote_estimates e ON e.quote_id = q.quote_id
                  WHERE e.quote_id IS NULL), 'zero'
UNION ALL SELECT 'quote_estimates', '5 Validity', 'any cost element negative',
                 (SELECT COUNT(*) FROM erp.quote_estimates
                  WHERE LEAST(est_board_cost, est_ink_cost, est_plate_cost, est_die_cost,
                              est_conversion_cost, est_freight_cost,
                              est_rework_allowance, est_overhead) < 0), 'zero'
UNION ALL SELECT 'quote_estimates', '5 Validity', 'est_total_cost <> sum of the 8 elements (tolerance 5)',
                 (SELECT COUNT(*) FROM erp.quote_estimates
                  WHERE ABS(est_total_cost - (  COALESCE(est_board_cost,0)  + COALESCE(est_ink_cost,0)
                                              + COALESCE(est_plate_cost,0)  + COALESCE(est_die_cost,0)
                                              + COALESCE(est_conversion_cost,0) + COALESCE(est_freight_cost,0)
                                              + COALESCE(est_rework_allowance,0) + COALESCE(est_overhead,0))) > 5), 'zero'
                  -- tolerance 5: each of the 8 elements is rounded to whole rupees (8 x 0.5 = 4)
UNION ALL SELECT 'quote_estimates', '5 Validity', 'est_board_cost <> kg x price/kg (tolerance 0.1%)',
                 (SELECT COUNT(*) FROM erp.quote_estimates
                  WHERE ABS(est_board_cost - est_board_kg * est_board_price_per_kg)
                        > 0.001 * est_board_cost), 'zero'
                  -- relative tolerance: kg is rounded to 0.1 and cost to whole rupees,
                  -- so the rounding error grows with the job size. A fixed Rs 1 gave false FAILs.

-- ------------------------------------------------- erp.quote_machine_hours
UNION ALL SELECT 'quote_machine_hours', '2 Uniqueness', 'duplicate quote_id + machine_code',
                 (SELECT COUNT(*) FROM (SELECT quote_id, machine_code FROM erp.quote_machine_hours
                                        GROUP BY quote_id, machine_code HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'quote_machine_hours', '4 Integrity', 'quote_id not in quotes',
                 (SELECT COUNT(*) FROM erp.quote_machine_hours h
                  LEFT JOIN erp.quotes q ON q.quote_id = h.quote_id
                  WHERE q.quote_id IS NULL), 'zero'
UNION ALL SELECT 'quote_machine_hours', '5 Validity', 'est_hours <= 0',
                 (SELECT COUNT(*) FROM erp.quote_machine_hours WHERE est_hours <= 0), 'zero'

-- ---------------------------------------------------------------- erp.dispatches
UNION ALL SELECT 'dispatches', '2 Uniqueness', 'duplicate dispatch_no',
                 (SELECT COUNT(*) FROM (SELECT dispatch_no FROM erp.dispatches
                                        GROUP BY dispatch_no HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'dispatches', '2 Uniqueness', 'jobs with more than one dispatch',
                 (SELECT COUNT(*) FROM (SELECT job_no FROM erp.dispatches
                                        GROUP BY job_no HAVING COUNT(*) > 1) d), 'info'
UNION ALL SELECT 'dispatches', '4 Integrity', 'job_no not in jobs',
                 (SELECT COUNT(*) FROM erp.dispatches d
                  LEFT JOIN erp.jobs j ON j.job_no = d.job_no
                  WHERE j.job_no IS NULL), 'zero'
UNION ALL SELECT 'dispatches', '5 Validity', 'cartons <= 0 or freight < 0',
                 (SELECT COUNT(*) FROM erp.dispatches
                  WHERE cartons <= 0 OR freight_cost_inr < 0), 'zero'
UNION ALL SELECT 'dispatches', '5 Validity', 'dispatched before the job was ordered',
                 (SELECT COUNT(*) FROM erp.dispatches d
                  JOIN erp.jobs j ON j.job_no = d.job_no
                  WHERE d.dispatch_date < j.order_date), 'zero'

-- ---------------------------------------------------------- finance.sales_invoices
UNION ALL SELECT 'sales_invoices', '2 Uniqueness', 'duplicate invoice_no',
                 (SELECT COUNT(*) FROM (SELECT invoice_no FROM finance.sales_invoices
                                        GROUP BY invoice_no HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'sales_invoices', '2 Uniqueness', 'job invoiced more than once (grain: 1 invoice per job)',
                 (SELECT COUNT(*) FROM (SELECT job_no FROM finance.sales_invoices
                                        GROUP BY job_no HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'sales_invoices', '4 Integrity', 'job_no not in jobs',
                 (SELECT COUNT(*) FROM finance.sales_invoices i
                  LEFT JOIN erp.jobs j ON j.job_no = i.job_no
                  WHERE j.job_no IS NULL), 'zero'
UNION ALL SELECT 'sales_invoices', '4 Integrity', 'customer_code not in customer master',
                 (SELECT COUNT(*) FROM finance.sales_invoices i
                  LEFT JOIN masters.customers c ON c.customer_code = i.customer_code
                  WHERE c.customer_code IS NULL), 'zero'
UNION ALL SELECT 'sales_invoices', '4 Integrity', 'job with no invoice',
                 (SELECT COUNT(*) FROM erp.jobs j
                  LEFT JOIN finance.sales_invoices i ON i.job_no = j.job_no
                  WHERE i.job_no IS NULL), 'info'
UNION ALL SELECT 'sales_invoices', '5 Validity', 'invoice customer <> job customer',
                 (SELECT COUNT(*) FROM finance.sales_invoices i
                  JOIN erp.jobs j ON j.job_no = i.job_no
                  WHERE i.customer_code <> j.customer_code), 'zero'
UNION ALL SELECT 'sales_invoices', '5 Validity', 'taxable_value <= 0',
                 (SELECT COUNT(*) FROM finance.sales_invoices WHERE taxable_value <= 0), 'zero'
UNION ALL SELECT 'sales_invoices', '5 Validity', 'taxable_value <> qty x rate / 1000 (tolerance 1)',
                 (SELECT COUNT(*) FROM finance.sales_invoices
                  WHERE ABS(taxable_value - qty * rate_per_1000 / 1000.0) > 1), 'zero'
UNION ALL SELECT 'sales_invoices', '5 Validity', 'INR invoice: GST <> 18% of taxable (tolerance 1)',
                 (SELECT COUNT(*) FROM finance.sales_invoices
                  WHERE currency = 'INR'
                    AND ABS(gst_18pct - 0.18 * taxable_value) > 1), 'zero'
UNION ALL SELECT 'sales_invoices', '5 Validity', 'USD (export) invoice with GST <> 0',
                 (SELECT COUNT(*) FROM finance.sales_invoices
                  WHERE currency = 'USD' AND gst_18pct <> 0), 'zero'   -- exports are zero-rated
UNION ALL SELECT 'sales_invoices', '5 Validity', 'invoice_total <> taxable + GST (tolerance 1)',
                 (SELECT COUNT(*) FROM finance.sales_invoices
                  WHERE ABS(invoice_total - (taxable_value + gst_18pct)) > 1), 'zero'
UNION ALL SELECT 'sales_invoices', '5 Validity', 'invoiced before the job was ordered',
                 (SELECT COUNT(*) FROM finance.sales_invoices i
                  JOIN erp.jobs j ON j.job_no = i.job_no
                  WHERE i.invoice_date < j.order_date), 'zero'
UNION ALL SELECT 'sales_invoices', '5 Validity', 'invoice currency <> customer billing currency',
                 (SELECT COUNT(*) FROM finance.sales_invoices i
                  JOIN masters.customers c ON c.customer_code = i.customer_code
                  WHERE i.currency <> c.billing_currency), 'zero'

-- ---------------------------------------------------------- finance.credit_notes
UNION ALL SELECT 'credit_notes', '2 Uniqueness', 'duplicate credit_note_no',
                 (SELECT COUNT(*) FROM (SELECT credit_note_no FROM finance.credit_notes
                                        GROUP BY credit_note_no HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'credit_notes', '4 Integrity', 'invoice_no not in invoices',
                 (SELECT COUNT(*) FROM finance.credit_notes n
                  LEFT JOIN finance.sales_invoices i ON i.invoice_no = n.invoice_no
                  WHERE i.invoice_no IS NULL), 'zero'
UNION ALL SELECT 'credit_notes', '5 Validity', 'credit note customer <> invoice customer',
                 (SELECT COUNT(*) FROM finance.credit_notes n
                  JOIN finance.sales_invoices i ON i.invoice_no = n.invoice_no
                  WHERE n.customer_code <> i.customer_code), 'zero'
UNION ALL SELECT 'credit_notes', '5 Validity', 'credit note currency <> invoice currency',
                 (SELECT COUNT(*) FROM finance.credit_notes n
                  JOIN finance.sales_invoices i ON i.invoice_no = n.invoice_no
                  WHERE n.currency <> i.currency), 'zero'
UNION ALL SELECT 'credit_notes', '5 Validity', 'amount <= 0 (stored as a positive number)',
                 (SELECT COUNT(*) FROM finance.credit_notes WHERE amount <= 0), 'zero'
UNION ALL SELECT 'credit_notes', '5 Validity', 'credit note dated before its invoice',
                 (SELECT COUNT(*) FROM finance.credit_notes n
                  JOIN finance.sales_invoices i ON i.invoice_no = n.invoice_no
                  WHERE n.cn_date < i.invoice_date), 'zero'
UNION ALL SELECT 'credit_notes', '5 Validity', 'credit notes exceed the invoice taxable value',
                 (SELECT COUNT(*) FROM (SELECT n.invoice_no, SUM(n.amount) AS cn_total
                                        FROM finance.credit_notes n GROUP BY n.invoice_no) s   -- aggregate BEFORE joining
                  JOIN finance.sales_invoices i ON i.invoice_no = s.invoice_no
                  WHERE s.cn_total > i.taxable_value), 'zero'

-- ------------------------------------------------------- finance.customer_receipts
UNION ALL SELECT 'customer_receipts', '2 Uniqueness', 'duplicate receipt_no',
                 (SELECT COUNT(*) FROM (SELECT receipt_no FROM finance.customer_receipts
                                        GROUP BY receipt_no HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'customer_receipts', '2 Uniqueness', 'invoices paid in more than one receipt',
                 (SELECT COUNT(*) FROM (SELECT invoice_no FROM finance.customer_receipts
                                        GROUP BY invoice_no HAVING COUNT(*) > 1) d), 'info'
UNION ALL SELECT 'customer_receipts', '4 Integrity', 'invoice_no not in invoices',
                 (SELECT COUNT(*) FROM finance.customer_receipts r
                  LEFT JOIN finance.sales_invoices i ON i.invoice_no = r.invoice_no
                  WHERE i.invoice_no IS NULL), 'zero'
UNION ALL SELECT 'customer_receipts', '4 Integrity', 'invoice with no receipt yet (receivable)',
                 (SELECT COUNT(*) FROM finance.sales_invoices i
                  LEFT JOIN finance.customer_receipts r ON r.invoice_no = i.invoice_no
                  WHERE r.invoice_no IS NULL), 'info'
UNION ALL SELECT 'customer_receipts', '5 Validity', 'amount <= 0',
                 (SELECT COUNT(*) FROM finance.customer_receipts WHERE amount <= 0), 'zero'
UNION ALL SELECT 'customer_receipts', '5 Validity', 'receipt dated before its invoice',
                 (SELECT COUNT(*) FROM finance.customer_receipts r
                  JOIN finance.sales_invoices i ON i.invoice_no = r.invoice_no
                  WHERE r.receipt_date < i.invoice_date), 'zero'
UNION ALL SELECT 'customer_receipts', '5 Validity', 'receipts exceed invoice total (tolerance 1)',
                 (SELECT COUNT(*) FROM (SELECT r.invoice_no, SUM(r.amount) AS paid
                                        FROM finance.customer_receipts r GROUP BY r.invoice_no) s
                  JOIN finance.sales_invoices i ON i.invoice_no = s.invoice_no
                  WHERE s.paid > i.invoice_total + 1), 'zero'

-- ---------------------------------------------------------- finance.fx_rates_usd_inr
UNION ALL SELECT 'fx_rates_usd_inr', '2 Uniqueness', 'duplicate rate_date + currency',
                 (SELECT COUNT(*) FROM (SELECT rate_date, currency FROM finance.fx_rates_usd_inr
                                        GROUP BY rate_date, currency HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'fx_rates_usd_inr', '3 Completeness', 'calendar days with no rate (weekends/holidays)',
                 (SELECT COUNT(*) FROM generate_series(
                         (SELECT MIN(rate_date) FROM finance.fx_rates_usd_inr),
                         (SELECT MAX(rate_date) FROM finance.fx_rates_usd_inr),
                         INTERVAL '1 day') AS g(d)
                  WHERE g.d::date NOT IN (SELECT rate_date FROM finance.fx_rates_usd_inr)), 'info'
UNION ALL SELECT 'fx_rates_usd_inr', '3 Completeness', 'USD invoice dates before the first FX rate',
                 (SELECT COUNT(*) FROM finance.sales_invoices
                  WHERE currency = 'USD'
                    AND invoice_date < (SELECT MIN(rate_date) FROM finance.fx_rates_usd_inr)), 'zero'
UNION ALL SELECT 'fx_rates_usd_inr', '5 Validity', 'rate NULL or <= 0',
                 (SELECT COUNT(*) FROM finance.fx_rates_usd_inr
                  WHERE inr_per_unit IS NULL OR inr_per_unit <= 0), 'zero'

-- ---------------------------------------------------------- masters.customers
UNION ALL SELECT 'customers', '2 Uniqueness', 'duplicate customer_code',
                 (SELECT COUNT(*) FROM (SELECT customer_code FROM masters.customers
                                        GROUP BY customer_code HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'customers', '2 Uniqueness', 'GSTIN shared by more than one code (same legal entity twice?)',
                 (SELECT COUNT(*) FROM (SELECT gstin FROM masters.customers WHERE gstin IS NOT NULL
                                        GROUP BY gstin HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'customers', '3 Completeness', 'Indian customer with no GSTIN',
                 (SELECT COUNT(*) FROM masters.customers
                  WHERE country = 'India' AND gstin IS NULL), 'zero'
UNION ALL SELECT 'customers', '4 Integrity', 'sales_rep_code not in sales rep master',
                 (SELECT COUNT(*) FROM masters.customers c
                  LEFT JOIN masters.sales_reps r ON r.sales_rep_code = c.sales_rep_code
                  WHERE r.sales_rep_code IS NULL), 'zero'
UNION ALL SELECT 'customers', '4 Integrity', 'sales_rep_code matches only if case is ignored',
                 (SELECT COUNT(*) FROM masters.customers c
                  LEFT JOIN masters.sales_reps r ON r.sales_rep_code = c.sales_rep_code
                  WHERE r.sales_rep_code IS NULL
                    AND UPPER(c.sales_rep_code) IN (SELECT UPPER(sales_rep_code) FROM masters.sales_reps)), 'info'
UNION ALL SELECT 'customers', '5 Validity', 'GSTIN not 15 characters',
                 (SELECT COUNT(*) FROM masters.customers
                  WHERE gstin IS NOT NULL AND length(gstin) <> 15), 'zero'
UNION ALL SELECT 'customers', '5 Validity', 'payment_terms_days <= 0',
                 (SELECT COUNT(*) FROM masters.customers WHERE payment_terms_days <= 0), 'zero'

-- ---------------------------------------------------------- masters.skus
UNION ALL SELECT 'skus', '2 Uniqueness', 'duplicate sku_code',
                 (SELECT COUNT(*) FROM (SELECT sku_code FROM masters.skus
                                        GROUP BY sku_code HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'skus', '4 Integrity', 'customer_code not in customer master',
                 (SELECT COUNT(*) FROM masters.skus s
                  LEFT JOIN masters.customers c ON c.customer_code = s.customer_code
                  WHERE c.customer_code IS NULL), 'zero'
UNION ALL SELECT 'skus', '4 Integrity', 'board_grade not in board grade master',
                 (SELECT COUNT(*) FROM masters.skus s
                  LEFT JOIN masters.board_grades b ON b.grade_code = s.board_grade
                  WHERE b.grade_code IS NULL), 'zero'
UNION ALL SELECT 'skus', '4 Integrity', 'sheet_format with no plate price',
                 (SELECT COUNT(*) FROM masters.skus s
                  WHERE s.sheet_format NOT IN (SELECT plate_format FROM masters.plate_price_list)), 'zero'
UNION ALL SELECT 'skus', '5 Validity', 'ups <= 0 or gsm <= 0',
                 (SELECT COUNT(*) FROM masters.skus WHERE ups <= 0 OR gsm <= 0), 'zero'
UNION ALL SELECT 'skus', '5 Validity', 'total_colours <> cmyk + spot + metallic',
                 (SELECT COUNT(*) FROM masters.skus
                  WHERE total_colours <> cmyk_colours + spot_colours + metallic), 'zero'
UNION ALL SELECT 'skus', '5 Validity', 'ups x blank area > sheet area (physically impossible)',
                 (SELECT COUNT(*) FROM masters.skus
                  WHERE ups::numeric * blank_w_mm * blank_h_mm > sheet_w_mm::numeric * sheet_h_mm), 'zero'
UNION ALL SELECT 'skus', '5 Validity', 'ink coverage outside 0..1',
                 (SELECT COUNT(*) FROM masters.skus
                  WHERE cov_cmyk NOT BETWEEN 0 AND 1
                     OR cov_spot NOT BETWEEN 0 AND 1
                     OR cov_met  NOT BETWEEN 0 AND 1), 'zero'

-- ---------------------------------------------------------- small masters
UNION ALL SELECT 'sales_reps', '2 Uniqueness', 'duplicate sales_rep_code',
                 (SELECT COUNT(*) FROM (SELECT sales_rep_code FROM masters.sales_reps
                                        GROUP BY sales_rep_code HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'estimators', '2 Uniqueness', 'duplicate estimator_code',
                 (SELECT COUNT(*) FROM (SELECT estimator_code FROM masters.estimators
                                        GROUP BY estimator_code HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'estimators', '5 Validity', 'left_on before joined_on',
                 (SELECT COUNT(*) FROM masters.estimators WHERE left_on < joined_on), 'zero'
UNION ALL SELECT 'operators', '2 Uniqueness', 'duplicate operator_code',
                 (SELECT COUNT(*) FROM (SELECT operator_code FROM masters.operators
                                        GROUP BY operator_code HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'board_grades', '2 Uniqueness', 'duplicate grade_code',
                 (SELECT COUNT(*) FROM (SELECT grade_code FROM masters.board_grades
                                        GROUP BY grade_code HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'board_price_history', '2 Uniqueness', 'duplicate month + grade',
                 (SELECT COUNT(*) FROM (SELECT month_start, grade_code FROM masters.board_price_history
                                        GROUP BY month_start, grade_code HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'board_price_history', '4 Integrity', 'grade_code not in board grade master',
                 (SELECT COUNT(*) FROM masters.board_price_history p
                  LEFT JOIN masters.board_grades b ON b.grade_code = p.grade_code
                  WHERE b.grade_code IS NULL), 'zero'
UNION ALL SELECT 'board_price_history', '3 Completeness', 'job with no board price for its order month + grade',
                 (SELECT COUNT(*) FROM erp.jobs j
                  JOIN masters.skus s ON s.sku_code = j.sku_code
                  LEFT JOIN masters.board_price_history p
                         ON p.grade_code  = s.board_grade
                        AND p.month_start = date_trunc('month', j.order_date)::date
                  WHERE p.grade_code IS NULL), 'zero'
UNION ALL SELECT 'ink_price_list', '2 Uniqueness', 'duplicate ink_code + effective_from',
                 (SELECT COUNT(*) FROM (SELECT ink_code, effective_from FROM masters.ink_price_list
                                        GROUP BY ink_code, effective_from HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'plate_price_list', '2 Uniqueness', 'duplicate plate_format + effective_from',
                 (SELECT COUNT(*) FROM (SELECT plate_format, effective_from FROM masters.plate_price_list
                                        GROUP BY plate_format, effective_from HAVING COUNT(*) > 1) d), 'zero'
UNION ALL SELECT 'plate_price_list', '3 Completeness', 'job ordered before the first plate price for its format',
                 (SELECT COUNT(*) FROM erp.jobs j
                  JOIN masters.skus s ON s.sku_code = j.sku_code
                  WHERE j.order_date < (SELECT MIN(p.effective_from) FROM masters.plate_price_list p
                                        WHERE p.plate_format = s.sheet_format)), 'zero'
UNION ALL SELECT 'rework_reasons', '2 Uniqueness', 'duplicate reason_code',
                 (SELECT COUNT(*) FROM (SELECT reason_code FROM masters.rework_reasons
                                        GROUP BY reason_code HAVING COUNT(*) > 1) d), 'zero'
)
SELECT tbl,
       family,
       check_name,
       failures,
       CASE WHEN expect = 'info' THEN 'INFO'
            WHEN failures = 0    THEN 'PASS'
            ELSE                      'FAIL'
       END AS status
FROM checks
ORDER BY CASE WHEN expect = 'zero' AND failures > 0 THEN 0 ELSE 1 END,   -- FAILs first
         tbl, family, check_name;


-- =============================================================================
-- PART B  PROFILES  (what does the data look like?)
-- =============================================================================

-- B1. Date coverage of every dated table. Drives the Dim Date range in Phase 3.
SELECT 'jobs.order_date'          AS column_name, MIN(order_date)   AS min_date, MAX(order_date)   AS max_date FROM erp.jobs
UNION ALL SELECT 'quotes.quote_date',             MIN(quote_date),   MAX(quote_date)   FROM erp.quotes
UNION ALL SELECT 'dispatches.dispatch_date',      MIN(dispatch_date),MAX(dispatch_date)FROM erp.dispatches
UNION ALL SELECT 'sales_invoices.invoice_date',   MIN(invoice_date), MAX(invoice_date) FROM finance.sales_invoices
UNION ALL SELECT 'credit_notes.cn_date',          MIN(cn_date),      MAX(cn_date)      FROM finance.credit_notes
UNION ALL SELECT 'customer_receipts.receipt_date',MIN(receipt_date), MAX(receipt_date) FROM finance.customer_receipts
UNION ALL SELECT 'fx_rates.rate_date',            MIN(rate_date),    MAX(rate_date)    FROM finance.fx_rates_usd_inr
UNION ALL SELECT 'board_price.month_start',       MIN(month_start),  MAX(month_start)  FROM masters.board_price_history
ORDER BY column_name;

-- B2. Jobs and invoices per Indian financial year (Apr-Mar). FY 26-27 is PARTIAL.
SELECT to_char(order_date - INTERVAL '3 months', 'YYYY') || '-'
    || to_char(order_date + INTERVAL '9 months', 'YY')   AS fy,
       COUNT(*)                                          AS jobs,
       MIN(order_date)                                   AS first_order,
       MAX(order_date)                                   AS last_order
FROM erp.jobs
GROUP BY 1
ORDER BY 1;

-- B3. Quote outcomes: how many quotes, how many won? (hit rate)
SELECT status,
       COUNT(*)                                              AS quotes,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_quotes   -- window over the grouped rows
FROM erp.quotes
GROUP BY status
ORDER BY quotes DESC;

-- B4. Currency mix of invoices (USD = export, zero-rated GST, needs FX conversion).
SELECT currency, COUNT(*) AS invoices, SUM(taxable_value) AS taxable_value_in_own_currency
FROM finance.sales_invoices
GROUP BY currency;

-- B5. Order quantity distribution (spot outliers before they distort averages).
SELECT MIN(order_qty)                                            AS min_qty,
       percentile_cont(0.25) WITHIN GROUP (ORDER BY order_qty)    AS p25,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY order_qty)    AS median,
       percentile_cont(0.75) WITHIN GROUP (ORDER BY order_qty)    AS p75,
       MAX(order_qty)                                            AS max_qty,
       ROUND(AVG(order_qty))                                     AS mean_qty
FROM erp.jobs;

-- B6. Credit note reasons (what goes wrong after invoicing?)
SELECT reason, COUNT(*) AS credit_notes
FROM finance.credit_notes
GROUP BY reason
ORDER BY credit_notes DESC;

-- B7. Customer master: codes per GSTIN (a GSTIN = one legal entity).
SELECT gstin,
       COUNT(*)                                        AS codes,
       string_agg(customer_code || ' / ' || customer_name, ' | ' ORDER BY customer_code) AS code_and_name
FROM masters.customers
WHERE gstin IS NOT NULL
GROUP BY gstin
HAVING COUNT(*) > 1
ORDER BY codes DESC, gstin;


-- =============================================================================
-- PART C  DRILL-DOWN TEMPLATES
-- When a Part A check FAILs, copy its WHERE logic here and SELECT the rows
-- instead of COUNT(*). Examples:
-- =============================================================================

-- C1. Which jobs use a customer code different from the SKU owner?
-- SELECT j.job_no, j.customer_code AS job_customer, s.customer_code AS sku_owner
-- FROM erp.jobs j JOIN masters.skus s ON s.sku_code = j.sku_code
-- WHERE s.customer_code <> j.customer_code
-- LIMIT 20;

-- C2. Quotes whose total does not equal the sum of their elements
-- SELECT quote_id, est_total_cost,
--        est_board_cost + est_ink_cost + est_plate_cost + est_die_cost
--      + est_conversion_cost + est_freight_cost + est_rework_allowance + est_overhead AS sum_of_elements
-- FROM erp.quote_estimates
-- WHERE ABS(est_total_cost - (est_board_cost + est_ink_cost + est_plate_cost + est_die_cost
--      + est_conversion_cost + est_freight_cost + est_rework_allowance + est_overhead)) > 1
-- LIMIT 20;
