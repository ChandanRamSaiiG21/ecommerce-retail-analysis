# Day 1: Data Acquisition and Profiling

## Objective
Understand the raw data before touching it. Every cleaning decision on Day 2 
was driven by what was found here. No assumptions, no skipping ahead.

---

## Why Profile Before Cleaning?

Most analysts open a dataset and start fixing things immediately. The problem 
with that approach is you end up fixing things you did not need to fix, missing 
things you should have fixed, and having no documented baseline to compare 
against after cleaning.

Profiling first gives you three things:
1. A written record of what the data looked like before any intervention
2. A prioritized list of issues so you fix Critical ones first
3. Defensible numbers you can cite in interviews and in the README

---

## Project Folder Structure

ecommerce-retail-analysis/
├── data/
│   ├── raw/          # Original CSVs, never modified
│   ├── cleaned/      # Output of 02_cleaning.ipynb
│   └── exports/      # Aggregated outputs for dashboards
├── notebooks/        # Jupyter notebooks, one per day
├── sql/
│   ├── schema/       # DDL scripts
│   ├── views/        # Analytical views
│   └── queries/      # Ad hoc queries
├── reports/
│   └── figures/      # EDA charts
├── excel/            # Standalone Excel deliverable
├── dashboards/       # Tableau and Looker Studio files
├── ml/
│   └── model_artifacts/
└── docs/             # Obsidian notes, rationale, interview prep

Rationale for keeping raw/ untouched: if cleaning introduces a bug, you can 
always go back to the source. Never overwrite raw data. This is standard 
data engineering practice and an interview talking point.

---

## Files Profiled

### orders (99,441 rows x 8 cols)

Key findings:
- All 5 timestamp columns stored as object dtype. Pandas reads CSVs as strings 
  by default. Datetime casting was required before any time-based calculation.
- Nulls in delivery columns are expected: orders that were never delivered 
  (cancelled, unavailable) will not have delivery timestamps.
- 8 distinct order statuses: delivered, shipped, canceled, unavailable, 
  invoiced, processing, created, approved.

Null breakdown rationale:
- order_approved_at: 160 nulls. Orders created but never approved, likely 
  abandoned before payment cleared.
- order_delivered_carrier_date: 1,783 nulls. Orders not yet picked up by carrier.
- order_delivered_customer_date: 2,965 nulls. Orders not yet received by customer.

These nulls are not errors. They are business states.

---

### order_items (112,650 rows x 7 cols)

Key findings:
- 112,650 rows for 99,441 orders means average 1.13 items per order.
- Max 21 items in a single order. Legitimate bulk purchase.
- Zero nulls. Cleanest file in the dataset.
- shipping_limit_date stored as object. Required datetime casting.

Why order_items is a separate table from orders:
- One order can have multiple items from multiple sellers.
- The grain of order_items is one row per item, not per order.
- Joining these two tables on order_id gives you item-level revenue analysis.

---

### payments (103,886 rows x 5 cols)

Key findings:
- 103,886 rows for 99,441 orders. More rows than orders means split payments exist.
- A customer can pay part by credit card and part by voucher in the same order.
- payment_type has "not_defined" with only 3 rows. No analytical value.
- Installments go up to 24 months. Brazil has a strong installment payment culture 
  (parcelamento). This is not unusual for the market.

Design decision: aggregate payments to one row per order before loading to 
PostgreSQL. This simplifies joins downstream. Kept payment_type_primary 
(dominant method) and payment_type_count (flags split payment orders).

---

### reviews (99,224 rows x 7 cols)

Key findings:
- review_comment_title: 88.3% null. Most customers do not write a title.
- review_comment_message: 58.7% null. Most customers only give a star rating.
- 814 non-unique review_ids affecting 1,603 rows.

The duplicate review_id investigation:
Same review_id was assigned to two different order_ids with identical text, 
score, and timestamps. This is a system-level bug in Olist's review platform, 
not a user action. A user cannot submit the same review to two different orders 
simultaneously. The platform likely had a race condition or ID generation bug.

Fix rationale: keep first occurrence per review_id. Dropping the duplicate 
preserves the review data without double-counting sentiment in any aggregation. 
Keeping both would inflate review counts and skew average scores.

---

### customers (99,441 rows x 5 cols)

Critical finding: two customer ID columns with different meanings.
- customer_id: one per order. If a person orders twice, they get two customer_ids.
- customer_unique_id: one per person across all orders.

This distinction is the most important thing to understand about this dataset.

Impact on analysis:
- RFM segmentation must use customer_unique_id as the person identifier.
- Cohort analysis must use customer_unique_id for the first purchase date.
- Using customer_id for RFM would make every customer appear to have purchased 
  exactly once, destroying the frequency and recency signals entirely.

Repeat buyer detection: 99,441 customer_ids but only 96,096 unique 
customer_unique_ids. This means 3,345 people placed more than one order.

---

### sellers (3,095 rows x 4 cols)

Clean file. Zero nulls, zero duplicates. No issues found.

---

### products (32,951 rows x 9 cols)

Key findings:
- Dimension columns (weight, length, height, width) have nulls.
- 13 product categories have no English translation in the translation file.

Null imputation strategy decided at profiling stage: use category median rather 
than global median. A product's dimensions are best estimated from similar 
products in the same category. A book and a refrigerator should not share the 
same imputed weight.

The 13 unmapped categories: these were transliterated manually rather than 
labelling them "unknown". Calling something "unknown" when you can actually 
read Portuguese and transliterate it is lazy and loses information.

---

### geolocation (1,000,163 rows x 5 cols)

Most complex file in the dataset.

Key findings:
- 261,831 exact duplicate rows (26.2% of the file). Same zip prefix, same 
  coordinates, same city, same state appearing multiple times. No analytical 
  value in keeping duplicates.
- 31 rows with coordinates outside Brazil's bounding box. Lat values up to 45 
  and lon values up to 121 are impossible for Brazil. These are data entry errors.
- Average 52.6 rows per zip prefix after deduplication, max 1,146.

Brazil bounding box used for clipping:
- Lat: -33.75 to 5.27
- Lon: -73.99 to -28.85

Aggregation strategy: after deduplication and outlier removal, aggregate to one 
row per zip prefix using median lat/lon. Median chosen over mean because it is 
more resistant to remaining coordinate noise within a zip prefix area.

Why aggregate to zip prefix level:
- The geolocation table is used to enrich customer and seller tables via 
  zip_code_prefix.
- Customers and sellers have one zip prefix each.
- Having 50+ lat/lon readings per zip prefix has no value for this use case.
- Aggregating reduces the table from 1,000,163 rows to 19,011 rows, one per 
  unique zip prefix.

---

### product_category_name_translation (71 rows x 2 cols)

Clean file. Used to join English category names to products at load time. 
Not kept as a separate table in the schema. Translation is a lookup that 
enriches products, not a standalone analytical entity.

---

## Key Integrity Checks

### Foreign key validation
Zero orphaned foreign keys across all joins. Every order_id in order_items 
exists in orders. Every customer_id in orders exists in customers. The dataset 
is internally referentially consistent.

### Ghost orders (775 orders with no line items)
- 603 unavailable
- 164 cancelled  
- 5 created
- 2 invoiced
- 1 shipped

The shipped ghost order (a68ce168) had a carrier date but no customer delivery 
confirmation, consistent with lost-in-transit in 2016. Not a data error.

Decision: flag ghost orders with has_items = False rather than dropping them. 
They are valid business events (cancellations, unavailable items) and belong 
in status-level analysis.

### One order with no payment record
Flagged with has_payment = False. Kept in the dataset for order status analysis 
but excluded from revenue calculations.

---

## Schema Design Decisions

Fact tables: orders, order_items
Dimension tables: customers, sellers, products, geolocation (aggregated)
Bridge tables: payments, reviews

Why payments and reviews are bridge tables:
- payments has a many-to-one relationship with orders (multiple payment methods 
  per order) but we aggregate it to one row per order before loading.
- reviews has a one-to-one relationship with orders in theory but the duplicate 
  review_id bug makes it behave like a bridge.

Why translation is not a separate table:
- It is a lookup used exactly once: to enrich products.
- Keeping it as a separate table would require an extra join in every 
  product-related query with no benefit.
- Joined at load time and the English name stored directly in dim_products.

---

## Data Quality Log Summary

20 issues documented with severity ratings.

Critical:
- All datetime columns stored as object dtype across 4 files
- 261,831 duplicate rows in geolocation
- 814 duplicate review_ids (system bug)
- customer_id vs customer_unique_id distinction

Medium:
- 2,965 null order_delivered_customer_date
- 13 product categories without English translation
- Product dimension nulls
- 31 geolocation coordinates outside Brazil bounding box
- 3 payment rows with not_defined type
- Split payments requiring aggregation

Low:
- review_comment_title 88.3% null (expected, not an error)
- review_comment_message 58.7% null (expected, not an error)
- Max 21 items per order (legitimate bulk purchase)
- Max 24 installments (normal for Brazilian market)

---

## Interview Talking Points

"Before writing a single line of cleaning code I profiled all 9 files and 
documented every issue I found. This gave me a prioritized fix list and a 
baseline to verify my cleaning work against."

"The most important discovery in profiling was the customer_id versus 
customer_unique_id distinction. Using the wrong column for RFM would have 
made every customer appear to have purchased exactly once."

"I found 814 duplicate review_ids and investigated the pattern before deciding 
how to handle them. The identical text, scores, and timestamps across two 
different order_ids confirmed this was a platform bug, not user behavior."