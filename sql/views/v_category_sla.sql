-- ============================================================
-- View: olist.v_category_sla
-- Purpose: Delivery SLA performance by product category
-- Business question: Which categories underperform on delivery?
-- Filters: 
--   - delivered orders only
--   - excludes has_placeholder_delivery_date = true (285 orders)
--   - minimum 30 orders per category to avoid small-sample noise
-- ============================================================

CREATE OR REPLACE VIEW olist.v_category_sla AS

WITH category_orders AS (
    SELECT
        p.product_category_name,
        fo.order_id,
        fo.days_to_deliver,
        fo.days_vs_estimate,
        fo.is_late,
        fo.order_purchase_timestamp::DATE  AS order_date
    FROM olist.fact_orders fo
    JOIN olist.fact_order_items foi
        ON fo.order_id = foi.order_id
    JOIN olist.dim_products p
        ON foi.product_id = p.product_id
    WHERE fo.order_status = 'delivered'
      AND fo.has_placeholder_delivery_date = FALSE
      AND p.product_category_name IS NOT NULL
),

category_stats AS (
    SELECT
        product_category_name,
        COUNT(DISTINCT order_id)                                AS total_orders,
        SUM(CASE WHEN is_late THEN 1 ELSE 0 END)               AS late_orders,
        ROUND(
            SUM(CASE WHEN is_late THEN 1 ELSE 0 END)::NUMERIC
            / COUNT(DISTINCT order_id) * 100, 2
        )                                                       AS late_rate_pct,
        ROUND(AVG(days_to_deliver)::NUMERIC, 1)                AS avg_days_to_deliver,
        ROUND(PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY days_to_deliver)::NUMERIC, 1)
                                                               AS median_days_to_deliver,
        ROUND(AVG(days_vs_estimate)::NUMERIC, 1)               AS avg_days_vs_estimate,
        ROUND(PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY days_vs_estimate)::NUMERIC, 1)
                                                               AS median_days_vs_estimate,
        ROUND(PERCENTILE_CONT(0.9)
            WITHIN GROUP (ORDER BY days_to_deliver)::NUMERIC, 1)
                                                               AS p90_days_to_deliver
    FROM category_orders
    GROUP BY product_category_name
    HAVING COUNT(DISTINCT order_id) >= 30
)

SELECT
    product_category_name,
    total_orders,
    late_orders,
    late_rate_pct,
    avg_days_to_deliver,
    median_days_to_deliver,
    p90_days_to_deliver,
    avg_days_vs_estimate,
    median_days_vs_estimate,
    -- Performance tier for dashboard colouring
    CASE
        WHEN late_rate_pct >= 10 THEN 'Critical'
        WHEN late_rate_pct >= 6.7 THEN 'Below Average'
        WHEN late_rate_pct >= 3 THEN 'Average'
        ELSE 'Good'
    END AS sla_tier
FROM category_stats
ORDER BY late_rate_pct DESC;


-- Validation 3A: overall shape and platform benchmark check
SELECT
    COUNT(*)                            AS total_categories,
    SUM(total_orders)                   AS total_orders_covered,
    ROUND(AVG(late_rate_pct), 2)        AS avg_late_rate,
    MAX(late_rate_pct)                  AS worst_category_rate,
    MIN(late_rate_pct)                  AS best_category_rate,
    COUNT(*) FILTER (WHERE sla_tier = 'Critical')       AS critical_count,
    COUNT(*) FILTER (WHERE sla_tier = 'Below Average')  AS below_avg_count
FROM olist.v_category_sla;


-- Validation 3B: top 10 worst categories — must match Excel
SELECT
    product_category_name,
    total_orders,
    late_rate_pct,
    avg_days_to_deliver,
    p90_days_to_deliver,
    sla_tier
FROM olist.v_category_sla
ORDER BY late_rate_pct DESC
LIMIT 10;