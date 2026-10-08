# Retail Customer Segmentation & Churn Risk Dashboard

RFM-based customer segmentation and churn-risk analysis on retail
transaction data, built with PostgreSQL (window functions, CTEs) and
Power BI.

## Business problem

Which customers are most likely to stop buying, and where should a
win-back campaign focus to protect the most revenue for the least
effort?

## Dataset

Online Retail II (UK-based online retailer, Dec 2009–Dec 2011),
~4,300 customers after cleaning, loaded into PostgreSQL as
`churn_project."Customer_Chrun_project"`.

## Method

1. **Clean the data.** Removed rows with no `CustomerID` or a
   non-positive `UnitPrice`. Cancellation invoices (`InvoiceNo`
   starting with `C`) were **kept**, not dropped — see *Data quality
   finding* below for why this matters.
2. **RFM scoring.** For each customer: Recency (days since last real
   order), Frequency (count of real orders), Monetary (total net
   revenue). Quartile-scored (1–4) with `NTILE()`.
3. **Segments.** Combined R/F/M scores into five named segments:
   High Value, Medium Value, New Customer, At Risk, Lost High
   Spender.
4. **Churn risk.** A customer is flagged "at risk" if they haven't
   ordered in 90+ days.
5. **Threshold justification.** Computed the 80th percentile gap
   between a customer's consecutive orders: 80% of repeat purchases
   happen within **70 days**, so a 90-day no-order window is a
   reasonable, slightly conservative churn-risk flag.
6. **Cohort retention.** Grouped customers by first-purchase month
   and tracked what % were still active in each following month.

## Data quality finding

The first version of the cleaning query filtered out cancellation
invoices (`WHERE InvoiceNo NOT LIKE 'C%'`) entirely. This is wrong:
a cancellation is a negative-quantity row that offsets an earlier
order. Deleting the cancellation while keeping the order it
cancels **inflates revenue** — a fully-refunded order still counted
as a sale.

Example found in the data: customer `12346` placed a single order
for 74,215 units, which was cancelled in full the same day. The
original cleaning logic counted the full order as revenue; the
corrected logic nets it to £0.

**Fix:** keep both the order and cancellation rows and let `SUM()`
net them out, instead of filtering cancellations out. This dropped
Total Revenue from £8.91M to £8.30M and Revenue at Risk from £1.04M
to £868K, and changed which segments hold the most at-risk revenue
(see below). The corrected logic is in
`sql/01_rfm_and_churn_views.sql`.

## Key findings

- **4,371** customers, **£8.30M** total revenue, **33%** flagged as
  churn risk (no order in 90+ days), **£868K** revenue at risk.
- **High Value** customers are ~32% of the customer base but bring
  in **£6.4M (77%)** of total revenue.
- **Two segments — Lost High Spender and At Risk — hold about 87%**
  of the £868K revenue at risk (£487K and £267K respectively).
  Medium Value, by comparison, holds only £114K.
- **Lost High Spender** customers were frequent, high-value buyers
  who have since gone quiet — the strongest win-back candidates.
  **At Risk** customers were never high-value, so they may be
  better suited to a lighter-touch (e.g. automated email) approach
  rather than the same high-touch campaign as Lost High Spender.
- **Retention drops sharply after month one** (from 100% to
  roughly 20–40%), then levels off rather than continuing to
  decline — most of the drop-off risk is in the first month after a
  customer's initial purchase.

## Recommendation

Target **Lost High Spender** and **At Risk** customers with a
win-back campaign; together they represent 87% of revenue at risk.
The dashboard includes an adjustable recovery-rate scenario
(0–40%, default 15%): at the default rate, this protects an
estimated **£113K** of revenue. This is framed as an estimate, not
a guaranteed result, since the dataset has no way to test an actual
campaign's outcome.

## Tools

- **PostgreSQL**: CTEs, window functions (`NTILE`, `LAG`,
  `PERCENTILE_CONT`), views
- **DBeaver**: query development and CSV export
- **Power BI Desktop**: data model, DAX measures, What-if parameter,
  4-page interactive report (Overview, Segments, Retention, Action)

## Repo contents

- `sql/01_rfm_and_churn_views.sql` — all views and analysis queries
- `Customer_Churn.pbix` — the Power BI dashboard file
- screenshots of each dashboard page

## How to reproduce

1. Load the Online Retail II dataset into a PostgreSQL table named
   `churn_project."Customer_Chrun_project"` with columns
   `InvoiceNo, StockCode, Description, Quantity, InvoiceDate,
   UnitPrice, CustomerID, Country`.
2. Run `sql/01_rfm_and_churn_views.sql` in order.
3. `SELECT * FROM churn_project.rfm_segments;` and
   `SELECT * FROM churn_project.cohort_retention;`, export each to
   CSV.
4. Open `Customer_Churn.pbix` in Power BI Desktop and point the two
   data sources at your exported CSVs (Transform data → Data source
   settings → Change Source).

## Caveats

- "Churn risk" (90+ days without an order) is a proxy, not a
  measured outcome — the dataset ends before any flagged customer's
  actual churn could be confirmed.
- Revenue-protected figures are scenario estimates based on an
  adjustable assumed recovery rate, not a backtested result.
