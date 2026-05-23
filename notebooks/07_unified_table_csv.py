import os
import pandas as pd
import psycopg2
from dotenv import load_dotenv

load_dotenv(r'D:\DataAnalyticsProjects\ecommerce-retail-analysis\.env')

# ── 1. Connect to PostgreSQL ──────────────────────────────────────────────────
conn = psycopg2.connect(
    host=os.getenv('DB_HOST'),
    port=os.getenv('DB_PORT'),
    dbname=os.getenv('DB_NAME'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD')
)

# ── 2. Pull order + product + SLA data (no RFM from view) ────────────────────
query = """
SELECT
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    o.order_id,
    DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month,
    EXTRACT('year'  FROM o.order_purchase_timestamp)::int AS order_year,
    EXTRACT('month' FROM o.order_purchase_timestamp)::int AS order_month_num,
    o.order_status,
    o.is_late,
    o.days_to_deliver,
    o.days_vs_estimate,
    oi.order_item_id,
    oi.price,
    oi.freight_value,
    p.product_category_name,
    p.product_category_name_english,
    sla.late_rate_pct        AS category_late_rate_pct,
    sla.avg_days_to_deliver  AS category_avg_days_to_deliver,
    sla.p90_days_to_deliver  AS category_p90_days_to_deliver,
    sla.sla_tier             AS category_sla_tier,
    sla.avg_days_vs_estimate AS category_avg_days_vs_estimate
FROM olist.fact_orders o
JOIN olist.dim_customers c
    ON o.customer_id = c.customer_id
JOIN olist.fact_order_items oi
    ON o.order_id = oi.order_id
JOIN olist.dim_products p
    ON oi.product_id = p.product_id
LEFT JOIN olist.v_category_sla sla
    ON p.product_category_name = sla.product_category_name
WHERE o.order_status = 'delivered'
"""

print("Pulling order data from PostgreSQL...")
df_orders = pd.read_sql(query, conn)
conn.close()
print(f"Order rows: {len(df_orders):,}")

# ── 3. Load original validated RFM snapshot (ground truth) ───────────────────
rfm_path = r'D:\DataAnalyticsProjects\ecommerce-retail-analysis\data\tableau\rfm_segments.csv'
rfm_orig = pd.read_csv(rfm_path)

rfm_slim = rfm_orig[[
    'customer_unique_id', 'segment', 'r_score', 'f_score',
    'm_score', 'rfm_total', 'recency_days', 'frequency', 'monetary'
]].drop_duplicates(subset='customer_unique_id')

print(f"RFM snapshot: {len(rfm_slim):,} unique customers")
print(f"Segment counts (ground truth):")
print(rfm_slim.groupby('segment')['customer_unique_id'].count().sort_values(ascending=False))

# ── 4. Merge RFM into orders ──────────────────────────────────────────────────
df = df_orders.merge(rfm_slim, on='customer_unique_id', how='left')
print(f"\nAfter merge: {len(df):,} rows")

# ── 5. Validate segment counts in unified table ───────────────────────────────
print("\nSegment counts in unified table (should match ground truth):")
print(df.groupby('segment')['customer_unique_id'].nunique().sort_values(ascending=False))

unmatched = df['segment'].isnull().sum()
print(f"\nCustomers with no RFM match: {unmatched:,}")

# ── 6. Validate totals ────────────────────────────────────────────────────────
print(f"\nTotal unique customers: {df['customer_unique_id'].nunique():,}")
print(f"Total rows: {len(df):,}")
print(f"Nulls per column:")
nulls = df.isnull().sum()
print(nulls[nulls > 0])

# ── 7. Export ─────────────────────────────────────────────────────────────────
output_path = r'D:\DataAnalyticsProjects\ecommerce-retail-analysis\data\tableau\unified_tableau.csv'
df.to_csv(output_path, index=False)
print(f"\nExported: {output_path}")
print(f"File size: {os.path.getsize(output_path) / 1024 / 1024:.1f} MB")
print(f"Columns ({len(df.columns)}): {list(df.columns)}")