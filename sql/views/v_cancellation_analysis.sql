-- ============================================================
-- View: olist.v_cancellation_analysis
-- Purpose: Cancellation patterns by state, category, and month
-- Business question: What drives order cancellations?
-- Fixes applied:
--   - monthly_stats: HAVING COUNT(*) >= 50 excludes boundary months
--   - order_categories: NULL category filtered out
-- Note: Includes 'unavailable' status as a cancellation variant
--       as these represent orders that couldn't be fulfilled
-- ============================================================

CREATE OR REPLACE VIEW olist.v_cancellation_analysis AS

WITH all_orders AS (
    SELECT
        fo.order_id,
        fo.order_status,
        fo.order_purchase_timestamp::DATE                       AS order_date,
        DATE_TRUNC('month', fo.order_purchase_timestamp)::DATE  AS order_month,
        c.customer_state,
        fo.approval_lag_hours,
        CASE
            WHEN fo.order_status IN ('canceled', 'unavailable') THEN 1
            ELSE 0
        END                                                     AS is_cancelled
    FROM olist.fact_orders fo
    JOIN olist.dim_customers c
        ON fo.customer_id = c.customer_id
),

order_categories AS (
    SELECT
        fo.order_id,
        fo.order_status,
        DATE_TRUNC('month', fo.order_purchase_timestamp)::DATE  AS order_month,
        c.customer_state,
        p.product_category_name,
        CASE
            WHEN fo.order_status IN ('canceled', 'unavailable') THEN 1
            ELSE 0
        END                                                     AS is_cancelled
    FROM olist.fact_orders fo
    JOIN olist.dim_customers c
        ON fo.customer_id = c.customer_id
    JOIN olist.fact_order_items foi
        ON fo.order_id = foi.order_id
    JOIN olist.dim_products p
        ON foi.product_id = p.product_id
    WHERE p.product_category_name IS NOT NULL
),

monthly_stats AS (
    SELECT
        order_month,
        COUNT(*)                                                AS total_orders,
        SUM(is_cancelled)                                       AS cancelled_orders,
        ROUND(SUM(is_cancelled)::NUMERIC / COUNT(*) * 100, 2)  AS cancel_rate_pct
    FROM all_orders
    GROUP BY order_month
    HAVING COUNT(*) >= 50
),

state_stats AS (
    SELECT
        customer_state,
        COUNT(*)                                                AS total_orders,
        SUM(is_cancelled)                                       AS cancelled_orders,
        ROUND(SUM(is_cancelled)::NUMERIC / COUNT(*) * 100, 2)  AS cancel_rate_pct
    FROM all_orders
    GROUP BY customer_state
    HAVING COUNT(*) >= 50
),

category_stats AS (
    SELECT
        product_category_name,
        COUNT(DISTINCT order_id)                                AS total_orders,
        SUM(is_cancelled)                                       AS cancelled_orders,
        ROUND(SUM(is_cancelled)::NUMERIC
            / COUNT(DISTINCT order_id) * 100, 2)               AS cancel_rate_pct
    FROM order_categories
    GROUP BY product_category_name
    HAVING COUNT(DISTINCT order_id) >= 30
)

SELECT
    'monthly'                   AS analysis_dimension,
    order_month::TEXT           AS dimension_value,
    total_orders,
    cancelled_orders,
    cancel_rate_pct,
    NULL::TEXT                  AS secondary_dimension
FROM monthly_stats

UNION ALL

SELECT
    'state'                     AS analysis_dimension,
    customer_state              AS dimension_value,
    total_orders,
    cancelled_orders,
    cancel_rate_pct,
    NULL::TEXT                  AS secondary_dimension
FROM state_stats

UNION ALL

SELECT
    'category'                  AS analysis_dimension,
    product_category_name       AS dimension_value,
    total_orders,
    cancelled_orders,
    cancel_rate_pct,
    NULL::TEXT                  AS secondary_dimension
FROM category_stats

ORDER BY analysis_dimension, cancel_rate_pct DESC;


-- Validation 5A: row counts by dimension
SELECT
    analysis_dimension,
    COUNT(*)                        AS dimension_rows,
    ROUND(AVG(cancel_rate_pct), 2)  AS avg_cancel_rate,
    MAX(cancel_rate_pct)            AS max_cancel_rate
FROM olist.v_cancellation_analysis
GROUP BY analysis_dimension
ORDER BY analysis_dimension;


-- Validation 5B: overall platform cancellation rate check
SELECT
    SUM(cancelled_orders)                               AS total_cancelled,
    SUM(total_orders)                                   AS total_orders,
    ROUND(SUM(cancelled_orders)::NUMERIC
        / SUM(total_orders) * 100, 2)                  AS platform_cancel_rate
FROM olist.v_cancellation_analysis
WHERE analysis_dimension = 'monthly';


-- Validation 5C: worst states and categories
SELECT analysis_dimension, dimension_value, total_orders, cancel_rate_pct
FROM olist.v_cancellation_analysis
WHERE analysis_dimension IN ('state', 'category')
  AND cancel_rate_pct > 5
ORDER BY analysis_dimension, cancel_rate_pct DESC
LIMIT 20;


