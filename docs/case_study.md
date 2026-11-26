# Case study: where Conquer Cartons' margin goes

**Client question.** "We quote every job carefully. Why is the P&L margin so far below what our quotes say, and which customers, products and decisions are causing it?"

**Scope.** All 7,345 jobs dispatched from 1-Apr-2024 to 30-Sep-2026 (₹135.5 Cr net revenue). Each job's quote, scaled to the ordered quantity, is compared with its invoiced revenue and its actual cost from stores, the shop-floor MES, QA and dispatch, under the company's costing policy.

## Answer in one line

The quotes promise **19.5%** margin; the P&L delivers **9.9%**. **₹12.9 Cr** (about ₹5.2 Cr a year) leaks between quote and invoice. It is a cost problem, not a price problem: revenue came in slightly above quote, and actual cost came in 12.5% over estimate.

## Where the cost overrun is (₹13.6 Cr)

| Cost element | Over estimate | What drives it |
|---|---|---|
| Machine time | ₹6.83 Cr | Make-ready under-quoted on short runs and on repeat orders smaller than their quote; one estimator's standards |
| Board | ₹3.54 Cr | Usage (waste), not price: +5.2% kg over estimate |
| Freight | ₹1.70 Cr | Multi-drop deliveries for three key accounts |
| Plates, rework, overhead | ₹2.19 Cr | Late artwork changes (new plates, rework), plus 4.5% overhead on all of the above |
| Dies | −₹0.75 Cr | Repeat orders re-quote a die that already exists (an over-estimate that hides part of the leak) |

## Three findings and what they are worth

1. **Three key accounts are loss-making: −4.6% margin on 25% of revenue.** They were quoted the thinnest margins and are the costliest to serve: short runs, rush orders, 3.9 drops per delivery, and (for one of them) payment in 122 days on 45-day terms. *Recommendation:* at the next price renewal, add a per-drop delivery charge, a rush surcharge and a minimum order quantity, and enforce payment terms. Freight recovery alone is worth about **₹52 L a year**.
2. **Make-ready is priced as if it scaled with quantity.** Runs under 25k cartons earn 1.3% against 15.2% on runs of 50k+. *Recommendation:* quote make-ready as a fixed charge per job, and re-quote repeat orders whose quantity changes by more than 20%. Short-run jobs overran by ₹5.24 Cr, about **₹2.1 Cr a year** at stake.
3. **One estimator's machine-hour standards are too low.** EST03 quotes 46% of jobs and overruns by 16%, against 7–11% for colleagues on the same customers. *Recommendation:* recalibrate make-ready standards and peer-review large EST03 quotes. Bringing EST03 to the team's average overrun (about 9%) would save about **₹1.3 Cr a year**.

**Quick wins:** charge back customer-caused rework (₹76.5 L to date, about ₹31 L a year) and target board waste on the worst customers and grades (₹3.19 Cr usage variance).

*The findings overlap (the key accounts order more short runs, and many of their quotes are by EST03), so the savings are not additive. A realistic combined target is ₹3–4 Cr a year, or 2–3 margin points.*

## How we know the numbers are right

- Net revenue ties to an independent SQL reconciliation to the paisa; actual cost matches a separate T-SQL implementation of the costing policy.
- The margin bridge closes to ₹0, and 55 of 55 data-quality checks pass.
- Data problems (duplicate customer codes, three job-number formats, an MES upgrade, missing quote links) were fixed by documented rules, and every fix has a check.
