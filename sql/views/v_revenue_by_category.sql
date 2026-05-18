-- ============================================================
-- View: olist.v_revenue_by_category
-- Purpose: Monthly revenue trend and order volume by category
-- Business question: What is the revenue trend by category?
-- Revenue = price + freight_value (total customer spend)
-- Filter: delivered orders only
-- ============================================================

CREATE OR REPLACE VIEW olist.v_revenue_by_category AS

WITH category_monthly AS (
    SELECT
        DATE_TRUNC('month', fo.order_purchase_timestamp)::DATE  AS order_month,
        p.product_category_name,
        COUNT(DISTINCT fo.order_id)                             AS total_orders,
        COUNT(foi.order_item_id)                                AS total_items,
        ROUND(SUM(foi.price)::NUMERIC, 2)                       AS product_revenue,
        ROUND(SUM(foi.freight_value)::NUMERIC, 2)               AS freight_revenue,
        ROUND(SUM(foi.price + foi.freight_value)::NUMERIC, 2)   AS total_revenue,
        ROUND(AVG(foi.price)::NUMERIC, 2)                       AS avg_item_price,
        ROUND(AVG(foi.price + foi.freight_value)::NUMERIC, 2)   AS avg_order_value
    FROM olist.fact_orders fo
    JOIN olist.fact_order_items foi
        ON fo.order_id = foi.order_id
    JOIN olist.dim_products p
        ON foi.product_id = p.product_id
    WHERE fo.order_status = 'delivered'
      AND p.product_category_name IS NOT NULL
    GROUP BY
        DATE_TRUNC('month', fo.order_purchase_timestamp)::DATE,
        p.product_category_name
),

-- Overall platform monthly totals for share calculation
platform_monthly AS (
    SELECT
        DATE_TRUNC('month', fo.order_purchase_timestamp)::DATE  AS order_month,
        ROUND(SUM(foi.price + foi.freight_value)::NUMERIC, 2)   AS platform_revenue
    FROM olist.fact_orders fo
    JOIN olist.fact_order_items foi
        ON fo.order_id = foi.order_id
    WHERE fo.order_status = 'delivered'
    GROUP BY DATE_TRUNC('month', fo.order_purchase_timestamp)::DATE
)

SELECT
    cm.order_month,
    cm.product_category_name,
    cm.total_orders,
    cm.total_items,
    cm.product_revenue,
    cm.freight_revenue,
    cm.total_revenue,
    cm.avg_item_price,
    cm.avg_order_value,
    pm.platform_revenue,
    ROUND(cm.total_revenue / pm.platform_revenue * 100, 2)      AS revenue_share_pct
FROM category_monthly cm
JOIN platform_monthly pm
    ON cm.order_month = pm.order_month
ORDER BY
    cm.order_month,
    cm.total_revenue DESC;


-- Validation 6A: shape and revenue check
SELECT
    COUNT(*)                            AS total_rows,
    COUNT(DISTINCT order_month)         AS months_covered,
    COUNT(DISTINCT product_category_name) AS categories_covered,
    ROUND(SUM(total_revenue)::NUMERIC, 0) AS sum_of_category_revenue
FROM olist.v_revenue_by_category;


-- Validation 6B: top 5 categories by total revenue across all months
SELECT
    product_category_name,
    SUM(total_orders)                           AS total_orders,
    ROUND(SUM(total_revenue)::NUMERIC, 0)       AS total_revenue,
    ROUND(AVG(revenue_share_pct)::NUMERIC, 2)   AS avg_monthly_share_pct
FROM olist.v_revenue_by_category
GROUP BY product_category_name
ORDER BY total_revenue DESC
LIMIT 5;


-- Validation 6C: November 2017 peak check — must be highest revenue month
SELECT
    order_month,
    ROUND(SUM(total_revenue)::NUMERIC, 0)   AS monthly_revenue,
    SUM(total_orders)                       AS monthly_orders
FROM olist.v_revenue_by_category
GROUP BY order_month
ORDER BY monthly_revenue DESC
LIMIT 5;