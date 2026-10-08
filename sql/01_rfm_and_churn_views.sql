-- =====================================================================
-- Retail Customer Segmentation & Churn Risk — SQL Views
-- Database: PostgreSQL
-- Source table: churn_project."Customer_Chrun_project"
--   (raw transactions: InvoiceNo, StockCode, Description, Quantity,
--    InvoiceDate, UnitPrice, CustomerID, Country)
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS churn_project;


-- ---------------------------------------------------------------------
-- 1. retail_clean
--    Cleans the raw data and computes line-level revenue.
--
--    Keeps cancellation invoices (InvoiceNo starting with 'C') instead
--    of filtering them out. A cancellation is a negative-quantity row
--    that offsets an earlier order. Deleting cancellations while
--    keeping the order they cancel inflates revenue for any order
--    that was fully or partially returned. Keeping both rows lets
--    SUM() net them out to the correct amount.
-- ---------------------------------------------------------------------
CREATE VIEW churn_project.retail_clean AS
SELECT
    "InvoiceNo",
    "StockCode",
    "Description",
    "Quantity",
    "InvoiceDate",
    "UnitPrice",
    "CustomerID",
    "Country",
    ("Quantity" * "UnitPrice") AS TotalPrice   -- line-level revenue
FROM churn_project."Customer_Chrun_project"
WHERE "CustomerID" IS NOT NULL                 -- drop guest/unknown customers
  AND "UnitPrice" > 0;                         -- drop £0 / data-entry rows


-- ---------------------------------------------------------------------
-- 2. rfm_base
--    One row per customer with Recency, Frequency, Monetary.
-- ---------------------------------------------------------------------
CREATE VIEW churn_project.rfm_base AS
SELECT
    "CustomerID",

    -- MAX() so a customer who ordered from more than one country still
    -- collapses to a single row instead of one row per country.
    MAX("Country") AS "Country",

    -- Days since the customer's most recent REAL order (cancellation-only
    -- invoices are excluded here, so a return doesn't count as "recent activity").
    (
      (SELECT MAX("InvoiceDate") FROM churn_project.retail_clean)::date
        - MAX(CASE WHEN "InvoiceNo" NOT LIKE 'C%' THEN "InvoiceDate" END)::date
    ) AS Recency,

    -- Count of distinct REAL orders only (a cancellation is not a purchase).
    COUNT(DISTINCT CASE WHEN "InvoiceNo" NOT LIKE 'C%' THEN "InvoiceNo" END) AS Frequency,

    -- Total net revenue. Includes cancellation rows (negative values),
    -- so a returned order nets to its true value instead of overcounting.
    SUM(TotalPrice) AS Monetary

FROM churn_project.retail_clean
GROUP BY "CustomerID"

-- Excludes customers whose ONLY invoices are cancellations — they have
-- no real order in this data to anchor Recency/Frequency to, so they
-- shouldn't be scored or segmented.
HAVING COUNT(DISTINCT CASE WHEN "InvoiceNo" NOT LIKE 'C%' THEN "InvoiceNo" END) > 0;


-- ---------------------------------------------------------------------
-- 3. rfm_scored
--    Splits all customers into quartiles (1 = lowest, 4 = highest) on
--    each of Recency, Frequency and Monetary using NTILE.
--
--    Note: Recency is ordered DESC so that customers with the SMALLEST
--    recency (most recent buyers) get the HIGHEST score — a high
--    R-score should mean "bought recently," not "hasn't bought in a while."
-- ---------------------------------------------------------------------
CREATE VIEW churn_project.rfm_scored AS
SELECT
    "CustomerID",
    "Country",
    Recency,
    Frequency,
    Monetary,
    NTILE(4) OVER (ORDER BY Recency DESC)  AS R_Score,
    NTILE(4) OVER (ORDER BY Frequency ASC) AS F_Score,
    NTILE(4) OVER (ORDER BY Monetary ASC)  AS M_Score
FROM churn_project.rfm_base;


-- ---------------------------------------------------------------------
-- 4. rfm_segments
--    Labels each customer with a segment name based on their R/F/M
--    scores. This is the table loaded into Power BI.
--
--      High Value          -> recent, frequent, high-spending
--      At Risk              -> not recent, infrequent, low-spending
--      New Customer          -> recent but not yet frequent (early days)
--      Lost High Spender    -> used to buy often, has gone quiet
--      Medium Value          -> everyone else (middle of the pack)
-- ---------------------------------------------------------------------
CREATE VIEW churn_project.rfm_segments AS
SELECT
    "CustomerID",
    "Country",
    Recency,
    Frequency,
    Monetary,
    R_Score,
    F_Score,
    M_Score,
    (R_Score + F_Score + M_Score) AS RFM_Total,
    CASE
        WHEN R_Score >= 3 AND F_Score >= 3 AND M_Score >= 3 THEN 'High Value'
        WHEN R_Score <= 2 AND F_Score <= 2 AND M_Score <= 2 THEN 'At Risk'
        WHEN R_Score >= 3 AND F_Score <= 2                  THEN 'New Customer'
        WHEN R_Score <= 2 AND F_Score >= 3                  THEN 'Lost High Spender'
        ELSE 'Medium Value'
    END AS Customer_Segment
FROM churn_project.rfm_scored;


-- Check the result
SELECT * FROM churn_project.rfm_segments;
