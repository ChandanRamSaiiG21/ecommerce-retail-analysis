-- ============================================================
-- View: olist.v_rfm_scores
-- Purpose: Customer RFM segmentation with labeled segments
-- Business question: Which customer segments drive revenue?
-- Reference date: 2018-10-17 (day after last order in dataset)
-- Join chain: fact_orders -> dim_customers (customer_id)
--             fact_orders -> bridge_payments (order_id)
-- ============================================================

CREATE OR REPLACE VIEW olist.v_rfm_scores AS

WITH reference_date AS (
    SELECT DATE '2018-10-17' AS ref_date
),

rfm_raw AS (
    SELECT
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        COUNT(DISTINCT fo.order_id)                          AS frequency,
        ROUND(SUM(bp.payment_value)::NUMERIC, 2)            AS monetary,
        MAX(fo.order_purchase_timestamp::DATE)               AS last_order_date,
        (SELECT ref_date FROM reference_date)
            - MAX(fo.order_purchase_timestamp::DATE)         AS recency_days
    FROM olist.fact_orders fo
    JOIN olist.dim_customers c
        ON fo.customer_id = c.customer_id
    JOIN olist.bridge_payments bp
        ON fo.order_id = bp.order_id
    WHERE fo.order_status = 'delivered'
    GROUP BY
        c.customer_unique_id,
        c.customer_city,
        c.customer_state
),

rfm_percentiles AS (
    SELECT
        customer_unique_id,
        customer_city,
        customer_state,
        recency_days,
        frequency,
        monetary,
        last_order_date,
        NTILE(4) OVER (ORDER BY recency_days DESC)  AS r_score,
        NTILE(4) OVER (ORDER BY frequency ASC)      AS f_score,
        NTILE(4) OVER (ORDER BY monetary ASC)       AS m_score
    FROM rfm_raw
),

rfm_scored AS (
    SELECT
        customer_unique_id,
        customer_city,
        customer_state,
        recency_days,
        frequency,
        monetary,
        last_order_date,
        r_score,
        f_score,
        m_score,
        (r_score + f_score + m_score) AS rfm_total
    FROM rfm_percentiles
)

SELECT
    customer_unique_id,
    customer_city,
    customer_state,
    recency_days,
    frequency,
    monetary,
    last_order_date,
    r_score,
    f_score,
    m_score,
    rfm_total,
    CASE
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 2                  THEN 'Loyal Customers'
        WHEN r_score >= 3 AND f_score = 1                   THEN 'Potential Loyalists'
        WHEN r_score = 2 AND f_score >= 3                   THEN 'At Risk'
        WHEN r_score = 1 AND f_score >= 3                   THEN 'Cannot Lose Them'
        WHEN r_score = 2 AND f_score = 2                    THEN 'Needs Attention'
        WHEN r_score = 1 AND f_score = 2                    THEN 'Hibernating'
        ELSE                                                     'Lost'
    END AS segment
FROM rfm_scored;



-- Validation 1A: row count and nulls
SELECT
    COUNT(*)                                        AS total_customers,
    COUNT(*) FILTER (WHERE segment IS NULL)         AS null_segments,
    COUNT(*) FILTER (WHERE monetary <= 0)           AS zero_monetary,
    MIN(recency_days)                               AS min_recency,
    MAX(recency_days)                               AS max_recency
FROM olist.v_rfm_scores;



-- Validation 1B: segment distribution
SELECT
    segment,
    COUNT(*)                                AS customer_count,
    ROUND(SUM(monetary)::NUMERIC, 0)        AS total_revenue,
    ROUND(AVG(recency_days)::NUMERIC, 0)    AS avg_recency_days,
    ROUND(AVG(frequency)::NUMERIC, 2)       AS avg_frequency
FROM olist.v_rfm_scores
GROUP BY segment
ORDER BY total_revenue DESC;


