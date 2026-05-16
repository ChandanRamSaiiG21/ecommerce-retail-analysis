-- =============================================================
-- Olist E-Commerce Star Schema
-- Created: Day 2
-- Schema: olist
-- =============================================================

CREATE SCHEMA IF NOT EXISTS olist;

-- =============================================================
-- DIMENSION: customers
-- customer_unique_id is the true person identifier
-- customer_id is order-scoped (one per order)
-- RFM and cohort analysis must use customer_unique_id
-- =============================================================
CREATE TABLE olist.dim_customers (
    customer_id             VARCHAR(50) PRIMARY KEY,
    customer_unique_id      VARCHAR(50) NOT NULL,
    customer_zip_code_prefix INTEGER,
    customer_city           VARCHAR(100),
    customer_state          CHAR(2)
);

-- =============================================================
-- DIMENSION: sellers
-- =============================================================
CREATE TABLE olist.dim_sellers (
    seller_id               VARCHAR(50) PRIMARY KEY,
    seller_zip_code_prefix  INTEGER,
    seller_city             VARCHAR(100),
    seller_state            CHAR(2)
);

-- =============================================================
-- DIMENSION: products
-- Translation joined at load time
-- Dimension nulls imputed with category median
-- =============================================================
CREATE TABLE olist.dim_products (
    product_id                      VARCHAR(50) PRIMARY KEY,
    product_category_name           VARCHAR(100),
    product_category_name_english   VARCHAR(100),
    product_name_length             INTEGER,
    product_description_length      INTEGER,
    product_photos_qty              INTEGER,
    product_weight_g                NUMERIC(10,2),
    product_length_cm               NUMERIC(10,2),
    product_height_cm               NUMERIC(10,2),
    product_width_cm                NUMERIC(10,2)
);

-- =============================================================
-- DIMENSION: geolocation
-- Aggregated to one row per zip prefix (median lat/lon)
-- Outliers clipped to Brazil bounding box
-- =============================================================
CREATE TABLE olist.dim_geolocation (
    zip_code_prefix     INTEGER PRIMARY KEY,
    geolocation_lat     NUMERIC(10,6),
    geolocation_lng     NUMERIC(10,6),
    geolocation_city    VARCHAR(100),
    geolocation_state   CHAR(2)
);

-- =============================================================
-- FACT: orders
-- Central fact table
-- has_items, has_payment: integrity flags
-- has_placeholder_delivery_date: data quality flag
-- days_to_deliver, is_late: derived, nulled where unreliable
-- =============================================================
CREATE TABLE olist.fact_orders (
    order_id                        VARCHAR(50) PRIMARY KEY,
    customer_id                     VARCHAR(50) REFERENCES olist.dim_customers(customer_id),
    order_status                    VARCHAR(20),
    order_purchase_timestamp        TIMESTAMP,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   TIMESTAMP,
    has_items                       BOOLEAN,
    has_payment                     BOOLEAN,
    has_placeholder_delivery_date   BOOLEAN,
    days_to_deliver                 NUMERIC(8,2),
    days_vs_estimate                NUMERIC(8,2),
    is_late                         BOOLEAN,
    approval_lag_hours              NUMERIC(8,2)
);

-- =============================================================
-- FACT: order_items
-- Grain: one row per item per order
-- Links orders to products and sellers
-- =============================================================
CREATE TABLE olist.fact_order_items (
    order_id            VARCHAR(50) REFERENCES olist.fact_orders(order_id),
    order_item_id       INTEGER,
    product_id          VARCHAR(50) REFERENCES olist.dim_products(product_id),
    seller_id           VARCHAR(50) REFERENCES olist.dim_sellers(seller_id),
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2),
    freight_value       NUMERIC(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

-- =============================================================
-- BRIDGE: payments
-- Aggregated to one row per order
-- payment_type_primary: dominant payment method
-- payment_type_count: flags split payment orders
-- =============================================================
CREATE TABLE olist.bridge_payments (
    order_id                VARCHAR(50) PRIMARY KEY REFERENCES olist.fact_orders(order_id),
    payment_value           NUMERIC(10,2),
    payment_installments    INTEGER,
    payment_type_primary    VARCHAR(30),
    payment_type_count      INTEGER
);

-- =============================================================
-- BRIDGE: reviews
-- Deduplicated on review_id (814 duplicates dropped)
-- has_comment: derived boolean
-- =============================================================
CREATE TABLE olist.bridge_reviews (
    review_id               VARCHAR(50) PRIMARY KEY,
    order_id                VARCHAR(50) REFERENCES olist.fact_orders(order_id),
    review_score            INTEGER CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP,
    has_comment             BOOLEAN
);

-- =============================================================
-- INDEXES
-- Built on every foreign key and every column used in WHERE,
-- GROUP BY, or JOIN in the planned SQL views
-- =============================================================

-- fact_orders
CREATE INDEX idx_fact_orders_customer_id 
    ON olist.fact_orders(customer_id);
CREATE INDEX idx_fact_orders_status 
    ON olist.fact_orders(order_status);
CREATE INDEX idx_fact_orders_purchase_ts 
    ON olist.fact_orders(order_purchase_timestamp);
CREATE INDEX idx_fact_orders_is_late 
    ON olist.fact_orders(is_late);

-- fact_order_items
CREATE INDEX idx_fact_order_items_product_id 
    ON olist.fact_order_items(product_id);
CREATE INDEX idx_fact_order_items_seller_id 
    ON olist.fact_order_items(seller_id);

-- bridge_reviews
CREATE INDEX idx_bridge_reviews_order_id 
    ON olist.bridge_reviews(order_id);

-- dim_customers
CREATE INDEX idx_dim_customers_unique_id 
    ON olist.dim_customers(customer_unique_id);
CREATE INDEX idx_dim_customers_state 
    ON olist.dim_customers(customer_state);

-- dim_geolocation
CREATE INDEX idx_dim_geolocation_state 
    ON olist.dim_geolocation(geolocation_state);




