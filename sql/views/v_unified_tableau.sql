
SELECT
    -- Customer & RFM dimensions
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    rfm.segment,
    rfm.r_score,
    rfm.f_score,
    rfm.m_score,
    rfm.rfm_total,
    rfm.recency_days,
    rfm.frequency,
    rfm.monetary,

    -- Order dimensions
    o.order_id,
    DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month,
    EXTRACT('year'  FROM o.order_purchase_timestamp)::int AS order_year,
    EXTRACT('month' FROM o.order_purchase_timestamp)::int AS order_month_num,
    o.order_status,
    o.is_late,
    o.days_to_deliver,
    o.days_vs_estimate,

    -- Item & Product dimensions
    oi.order_item_id,
    oi.price,
    oi.freight_value,
    p.product_category_name,
    p.product_category_name_english,

    -- Category SLA (left join — not all categories have SLA data)
    sla.late_rate_pct        AS category_late_rate_pct,
    sla.avg_days_to_deliver  AS category_avg_days_to_deliver,
    sla.p90_days_to_deliver  AS category_p90_days_to_deliver,
    sla.sla_tier             AS category_sla_tier,
    sla.avg_days_vs_estimate AS category_avg_days_vs_estimate

FROM olist.fact_orders o

JOIN olist.dim_customers c
    ON o.customer_id = c.customer_id

JOIN olist.v_rfm_scores rfm
    ON c.customer_unique_id = rfm.customer_unique_id

JOIN olist.fact_order_items oi
    ON o.order_id = oi.order_id

JOIN olist.dim_products p
    ON oi.product_id = p.product_id

LEFT JOIN olist.v_category_sla sla
    ON p.product_category_name = sla.product_category_name

WHERE o.order_status = 'delivered'



