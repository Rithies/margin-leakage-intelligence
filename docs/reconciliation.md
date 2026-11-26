# Reconciliation

Three independent routes to the same numbers.

| Control total | Power BI model | SQL reconciliation (`sql/04_reconciliation.sql`) | T-SQL replica of the costing policy | Answer key (fill in) |
|---|---:|---:|---:|---:|
| Jobs | 7,345 | 7,345 | 7,345 | |
| Gross revenue (₹) | 1,358,176,226.34 | 1,358,176,226.34 | 1,358,176,226.34 | |
| Credit notes (₹) | 3,347,530.07 | 3,347,530.07 | 3,347,530.07 | |
| Net revenue (₹) | 1,354,828,696.27 | 1,354,828,696.27 | 1,354,828,696.27 | |
| Quoted revenue (₹) | 1,348,604,773.33 | — | 1,348,604,773 | |
| Estimated cost (₹) | 1,085,220,805.78 | — | 1,085,220,960 | |
| Actual cost (₹) | 1,220,839,265.15 | — | 1,220,839,265 | |
| Quoted margin | 19.53% | — | 19.53% | |
| Actual margin | 9.89% | — | 9.89% | |
| Unabsorbed machine hours | 572.28 | — | 572.28 | |
| Unabsorbed machine cost (₹) | 2,533,482.40 | — | 2,533,482.40 | |

**The one difference I traced:** estimated cost is ₹154 lower in the model than in the replica (0.00001%). The replica uses each quote's `est_total_cost`; the model adds up the 8 cost elements (needed to compare estimate and actual by element). Each element is rounded to whole rupees in the source, so the elements don't add up exactly to the total (D-11). The model's figure is the one that ties to the element-level bridge.

**Phase 6 step for me:** open `Conquer_JobCosting_v2/data/_answer_key_DO_NOT_OPEN/control_totals.json`, fill in the last column, and trace any difference above ±0.1%.

## Actual cost by element (₹)

| Element | Model |
|---|---:|
| Board | 647,788,353 |
| Ink | 69,625,456 |
| Plates | 13,047,741 |
| Dies | 11,699,600 |
| Machine time | 357,386,628 |
| Rework | 16,970,944 |
| Freight | 51,748,518 |
| Overhead (4.5%) | 52,572,026 |
