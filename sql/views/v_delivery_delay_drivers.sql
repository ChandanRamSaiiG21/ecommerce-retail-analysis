-- ============================================================
-- View: olist.v_delivery_delay_drivers
-- Purpose: Feature set for delivery delay prediction model
-- Business question: What drives late deliveries?
-- ML target: is_late (binary classification)
-- Scope: delivered orders only, no placeholder delivery dates
-- Features: order-level, seller-level, product-level, geo-level
-- ============================================================

CREATE OR REPLACE VIEW olist.v_delivery_delay_drivers AS

WITH order_base AS (
    SELECT
        fo.order_id,
        fo.customer_id,
        fo.order_status,
        fo.order_purchase_timestamp,
        fo.order_purchase_timestamp::DATE                       AS order_date,
        DATE_TRUNC('month', fo.order_purchase_timestamp)::DATE  AS order_month,
        EXTRACT(DOW FROM fo.order_purchase_timestamp)           AS order_day_of_week,
        EXTRACT(HOUR FROM fo.order_purchase_timestamp)          AS order_hour,
        EXTRACT(MONTH FROM fo.order_purchase_timestamp)         AS order_month_num,
        fo.days_to_deliver,
        fo.days_vs_estimate,
        fo.is_late,
        fo.approval_lag_hours,
        fo.has_items,
        fo.has_payment
    FROM olist.fact_orders fo
    WHERE fo.order_status = 'delivered'
      AND fo.has_placeholder_delivery_date = FALSE
      AND fo.has_items = TRUE
      AND fo.has_payment = TRUE
),

order_items_agg AS (
    -- Item-level features aggregated to order level
    SELECT
        foi.order_id,
        COUNT(foi.order_item_id)                                AS item_count,
        COUNT(DISTINCT foi.seller_id)                           AS seller_count,
        ROUND(SUM(foi.price)::NUMERIC, 2)                       AS order_value,
        ROUND(SUM(foi.freight_value)::NUMERIC, 2)               AS freight_value,
        ROUND(AVG(foi.price)::NUMERIC, 2)                       AS avg_item_price,
        ROUND(
            SUM(foi.freight_value) / NULLIF(SUM(foi.price), 0)
            * 100, 2
        )                                                       AS freight_ratio_pct
    FROM olist.fact_order_items foi
    GROUP BY foi.order_id
),

product_features AS (
    -- Physical product characteristics (weight, dimensions)
    SELECT
        foi.order_id,
        ROUND(AVG(p.product_weight_g)::NUMERIC, 1)              AS avg_product_weight_g,
        ROUND(AVG(
            COALESCE(p.product_length_cm, 0) *
            COALESCE(p.product_height_cm, 0) *
            COALESCE(p.product_width_cm, 0)
        )::NUMERIC, 1)                                          AS avg_product_volume_cm3,
        MODE() WITHIN GROUP (ORDER BY p.product_category_name)  AS primary_category
    FROM olist.fact_order_items foi
    JOIN olist.dim_products p
        ON foi.product_id = p.product_id
    GROUP BY foi.order_id
),

seller_features AS (
    -- Seller historical performance (lag indicator)
    SELECT
        foi.seller_id,
        COUNT(DISTINCT fo.order_id)                             AS seller_total_orders,
        ROUND(AVG(CASE WHEN fo.is_late THEN 1.0 ELSE 0.0 END)
            * 100, 2)                                           AS seller_hist_late_rate,
        ROUND(AVG(fo.days_to_deliver)::NUMERIC, 1)              AS seller_avg_days_to_deliver
    FROM olist.fact_orders fo
    JOIN olist.fact_order_items foi
        ON fo.order_id = foi.order_id
    WHERE fo.order_status = 'delivered'
      AND fo.has_placeholder_delivery_date = FALSE
    GROUP BY foi.seller_id
),

customer_state_features AS (
    SELECT
        c.customer_id,
        c.customer_state,
        c.customer_city
    FROM olist.dim_customers c
)

SELECT
    ob.order_id,

    -- Target variable
    ob.is_late,

    -- Time features
    ob.order_day_of_week,
    ob.order_hour,
    ob.order_month_num,

    -- Order value features
    oia.item_count,
    oia.seller_count,
    oia.order_value,
    oia.freight_value,
    oia.avg_item_price,
    oia.freight_ratio_pct,

    -- Product physical features
    pf.avg_product_weight_g,
    pf.avg_product_volume_cm3,
    pf.primary_category,

    -- Seller performance features
    sf.seller_hist_late_rate,
    sf.seller_avg_days_to_deliver,
    sf.seller_total_orders,

    -- Geography
    csf.customer_state,

    -- Approval lag (operational friction)
    ob.approval_lag_hours

FROM order_base ob
JOIN order_items_agg oia       ON ob.order_id = oia.order_id
JOIN product_features pf       ON ob.order_id = pf.order_id
JOIN customer_state_features csf ON ob.customer_id = csf.customer_id
-- Seller join: take the primary seller per order
JOIN olist.fact_order_items foi_primary
    ON ob.order_id = foi_primary.order_id
    AND foi_primary.order_item_id = 1
JOIN seller_features sf
    ON foi_primary.seller_id = sf.seller_id;


-- Validation 7A: row count, target balance, null check
SELECT
    COUNT(*)                                        AS total_orders,
    SUM(CASE WHEN is_late THEN 1 ELSE 0 END)        AS late_orders,
    ROUND(
        SUM(CASE WHEN is_late THEN 1 ELSE 0 END)::NUMERIC
        / COUNT(*) * 100, 2
    )                                               AS late_rate_pct,
    COUNT(*) FILTER (WHERE avg_product_weight_g IS NULL) AS null_weight,
    COUNT(*) FILTER (WHERE seller_hist_late_rate IS NULL) AS null_seller_rate,
    COUNT(*) FILTER (WHERE approval_lag_hours IS NULL)    AS null_approval_lag
FROM olist.v_delivery_delay_drivers;

-- Validation 7B: feature sanity check
SELECT
    ROUND(AVG(item_count)::NUMERIC, 2)              AS avg_items,
    ROUND(AVG(order_value)::NUMERIC, 2)             AS avg_order_value,
    ROUND(AVG(avg_product_weight_g)::NUMERIC, 1)    AS avg_weight_g,
    ROUND(AVG(seller_hist_late_rate)::NUMERIC, 2)   AS avg_seller_late_rate,
    ROUND(AVG(approval_lag_hours)::NUMERIC, 1)      AS avg_approval_lag_hrs,
    COUNT(DISTINCT customer_state)                  AS distinct_states,
    COUNT(DISTINCT primary_category)                AS distinct_categories
FROM olist.v_delivery_delay_drivers;