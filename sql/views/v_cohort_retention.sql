-- ============================================================
-- View: olist.v_cohort_retention
-- Purpose: Month-over-month cohort retention matrix
-- Business question: What is the cohort retention trend?
-- Logic: Cohort = month of customer's first order
--        Period = months since first order (0, 1, 2, ...)
--        Retention = % of cohort active in that period
-- Note: Olist is a marketplace — repeat purchase rate is low
--       by design. This view will confirm that finding.
-- ============================================================

CREATE OR REPLACE VIEW olist.v_cohort_retention AS

WITH first_orders AS (
    -- One row per customer: their cohort month
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(fo.order_purchase_timestamp))::DATE AS cohort_month
    FROM olist.fact_orders fo
    JOIN olist.dim_customers c
        ON fo.customer_id = c.customer_id
    WHERE fo.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
),

customer_orders AS (
    -- All orders per customer with their order month
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', fo.order_purchase_timestamp)::DATE AS order_month
    FROM olist.fact_orders fo
    JOIN olist.dim_customers c
        ON fo.customer_id = c.customer_id
    WHERE fo.order_status NOT IN ('canceled', 'unavailable')
),

cohort_activity AS (
    -- Join to get period number for each order
    SELECT
        f.cohort_month,
        co.order_month,
        co.customer_unique_id,
        -- Months since first order
        (EXTRACT(YEAR FROM co.order_month) - EXTRACT(YEAR FROM f.cohort_month)) * 12
        + (EXTRACT(MONTH FROM co.order_month) - EXTRACT(MONTH FROM f.cohort_month))
            AS period_number
    FROM customer_orders co
    JOIN first_orders f
        ON co.customer_unique_id = f.customer_unique_id
),

cohort_sizes AS (
    -- How many customers in each cohort (period 0)
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM cohort_activity
    WHERE period_number = 0
    GROUP BY cohort_month
),

cohort_period_active AS (
    -- How many customers active in each period
    SELECT
        cohort_month,
        period_number,
        COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM cohort_activity
    GROUP BY cohort_month, period_number
)

SELECT
    cpa.cohort_month,
    cs.cohort_size,
    cpa.period_number,
    cpa.active_customers,
    ROUND(
        (cpa.active_customers::NUMERIC / cs.cohort_size) * 100, 2
    ) AS retention_rate_pct
FROM cohort_period_active cpa
JOIN cohort_sizes cs
    ON cpa.cohort_month = cs.cohort_month
WHERE cpa.cohort_month >= DATE '2016-10-01'  -- first full cohort
  AND cpa.cohort_month <= DATE '2018-08-01'  -- last cohort with follow-up data
ORDER BY
    cpa.cohort_month,
    cpa.period_number;




-- Validation 2A: shape check
SELECT
    COUNT(*)                        AS total_rows,
    COUNT(DISTINCT cohort_month)    AS cohort_count,
    MAX(period_number)              AS max_period,
    MIN(retention_rate_pct)         AS min_retention,
    MAX(retention_rate_pct)         AS max_retention
FROM olist.v_cohort_retention;



-- Validation 2B: period 0 must always be 100%
SELECT
    cohort_month,
    cohort_size,
    retention_rate_pct
FROM olist.v_cohort_retention
WHERE period_number = 0
ORDER BY cohort_month;


-- Validation 2C: spot check retention drop-off
SELECT
    period_number,
    ROUND(AVG(retention_rate_pct), 2)   AS avg_retention_pct,
    ROUND(MAX(retention_rate_pct), 2)   AS max_retention_pct
FROM olist.v_cohort_retention
WHERE period_number <= 6
GROUP BY period_number
ORDER BY period_number;


-- Validation 2D: period 1 retention excluding the singleton cohort
SELECT
    cohort_month,
    cohort_size,
    active_customers,
    retention_rate_pct
FROM olist.v_cohort_retention
WHERE period_number = 1
  AND cohort_size > 10
ORDER BY retention_rate_pct DESC
LIMIT 10;