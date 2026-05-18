-- ============================================================
-- View: olist.v_seller_performance
-- Purpose: Seller-level SLA, revenue, and review performance
-- Business question: Which sellers underperform on delivery SLA?
-- Filters: delivered orders, no placeholder delivery dates
-- Minimum 10 orders per seller to exclude micro-sellers
-- ============================================================

CREATE OR REPLACE VIEW olist.v_seller_performance AS

WITH seller_orders AS (
    SELECT
        foi.seller_id,
        fo.order_id,
        fo.is_late,
        fo.days_to_deliver,
        fo.days_vs_estimate,
        fo.has_placeholder_delivery_date,
        foi.price,
        foi.freight_value,
        br.review_score
    FROM olist.fact_orders fo
    JOIN olist.fact_order_items foi
        ON fo.order_id = foi.order_id
    LEFT JOIN olist.bridge_reviews br
        ON fo.order_id = br.order_id
    WHERE fo.order_status = 'delivered'
      AND fo.has_placeholder_delivery_date = FALSE
),

seller_stats AS (
    SELECT
        s.seller_id,
        s.seller_city,
        s.seller_state,
        COUNT(DISTINCT so.order_id)                             AS total_orders,
        ROUND(SUM(so.price + so.freight_value)::NUMERIC, 2)    AS total_revenue,
        ROUND(AVG(so.price + so.freight_value)::NUMERIC, 2)    AS avg_order_value,
        SUM(CASE WHEN so.is_late THEN 1 ELSE 0 END)            AS late_orders,
        ROUND(
            SUM(CASE WHEN so.is_late THEN 1 ELSE 0 END)::NUMERIC
            / COUNT(DISTINCT so.order_id) * 100, 2
        )                                                       AS late_rate_pct,
        ROUND(AVG(so.days_to_deliver)::NUMERIC, 1)             AS avg_days_to_deliver,
        ROUND(AVG(so.days_vs_estimate)::NUMERIC, 1)            AS avg_days_vs_estimate,
        ROUND(AVG(so.review_score)::NUMERIC, 2)                AS avg_review_score,
        COUNT(so.review_score)                                  AS reviews_received
    FROM seller_orders so
    JOIN olist.dim_sellers s
        ON so.seller_id = s.seller_id
    GROUP BY
        s.seller_id,
        s.seller_city,
        s.seller_state
    HAVING COUNT(DISTINCT so.order_id) >= 10
)

SELECT
    seller_id,
    seller_city,
    seller_state,
    total_orders,
    total_revenue,
    avg_order_value,
    late_orders,
    late_rate_pct,
    avg_days_to_deliver,
    avg_days_vs_estimate,
    avg_review_score,
    reviews_received,
    -- Risk flag: high volume + high late rate = operational risk
    CASE
        WHEN late_rate_pct >= 20 AND total_orders >= 50  THEN 'High Risk'
        WHEN late_rate_pct >= 10 AND total_orders >= 20  THEN 'Elevated Risk'
        WHEN late_rate_pct < 6.7 AND total_orders >= 50  THEN 'Strong Performer'
        ELSE 'Average'
    END AS seller_risk_tier
FROM seller_stats
ORDER BY total_revenue DESC;


-- Validation 4A: shape and sanity
SELECT
    COUNT(*)                                                    AS total_sellers,
    ROUND(SUM(total_revenue)::NUMERIC, 0)                      AS platform_revenue,
    ROUND(AVG(late_rate_pct)::NUMERIC, 2)                      AS avg_seller_late_rate,
    COUNT(*) FILTER (WHERE seller_risk_tier = 'High Risk')     AS high_risk_sellers,
    COUNT(*) FILTER (WHERE seller_risk_tier = 'Strong Performer') AS strong_sellers,
    MIN(avg_review_score)                                       AS min_review_score,
    MAX(avg_review_score)                                       AS max_review_score
FROM olist.v_seller_performance;


-- Validation 4B: top 10 sellers by revenue with their risk tier
SELECT
    seller_id,
    seller_state,
    total_orders,
    total_revenue,
    late_rate_pct,
    avg_review_score,
    seller_risk_tier
FROM olist.v_seller_performance
ORDER BY total_revenue DESC
LIMIT 10;


-- Validation 4C: high risk sellers — the ones that matter operationally
SELECT
    seller_id,
    seller_state,
    total_orders,
    late_rate_pct,
    avg_days_to_deliver,
    avg_review_score,
    seller_risk_tier
FROM olist.v_seller_performance
WHERE seller_risk_tier = 'High Risk'
ORDER BY late_rate_pct DESC
LIMIT 10;