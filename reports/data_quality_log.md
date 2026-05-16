# Data Quality Log — Olist E-Commerce Dataset
**Profiled:** Day 1  
**Profiled by:** Chandan  
**Dataset:** Olist Brazilian E-Commerce (Kaggle)  
**Files:** 9 CSVs  

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 4 |
| Medium   | 10 |
| Low      | 6 |

---

## orders (99,441 rows × 8 cols)

| # | Issue | Severity | Fix (Day 2) |
|---|-------|----------|-------------|
| O1 | All 5 timestamp cols are dtype object (string) | Critical | pd.to_datetime() on all 5 cols |
| O2 | order_approved_at: 160 nulls (0.16%) | Medium | Leave null; valid for cancelled orders |
| O3 | order_delivered_carrier_date: 1,783 nulls (1.79%) | Medium | Leave null; unshipped orders |
| O4 | order_delivered_customer_date: 2,965 nulls (2.98%) | Medium | Leave null; key for SLA; flag as is_late |
| O5 | order_status: 8 distinct values. Confirm all valid. | Low | Value count check, document all 8 |

---

## order_items (112,650 rows × 7 cols)

| # | Issue | Severity | Fix (Day 2) |
|---|-------|----------|-------------|
| I1 | shipping_limit_date stored as object | Critical | pd.to_datetime() |
| I2 | 112,650 items for 99,441 orders ie multi-item orders | Low | Expected; max 21 items per order |

---

## payments (103,886 rows × 5 cols)

| # | Issue | Severity | Fix (Day 2) |
|---|-------|----------|-------------|
| P1 | 103,886 rows for 99,441 orders ie split payments | Medium | Sum by order_id for revenue calc |
| P2 | payment_type = "not_defined": 3 rows | Low (downgraded from Medium) | Map to "other" - 0.003% of data, negligible |


---

## reviews (99,224 rows × 7 cols)

| # | Issue | Severity | Fix (Day 2) |
|---|-------|----------|-------------|
| R1 | review_comment_title: 88.3% null | Critical | Drop from ML features entirely |
| R2 | review_comment_message: 58.7% null | Medium | Retain col, flag as has_comment binary |
| R3 | review_id non-unique: 814 duplicate IDs, 1,603 rows affected | Medium | Pattern: same review_id across different order_ids (system bug). Fix: drop_duplicates(subset=["review_id"], keep="first") |
| R3b | Duplicate review_ids linked to different order_ids - system-level bug, not user re-review | Medium | Same review text/score/timestamp on two different order_ids. Not a customer action - Olist review system assigned same ID to multiple orders in one session. |
| R4 | Timestamp cols stored as object | Low | pd.to_datetime() |

---

## customers (99,441 rows × 5 cols)

| # | Issue | Severity | Fix (Day 2) |
|---|-------|----------|-------------|
| C1 | 99,441 customer_id vs 96,096 customer_unique_id | Medium | Use customer_unique_id for RFM - same person, multiple orders |

---

## geolocation (1,000,163 rows × 5 cols)

| # | Issue | Severity | Fix (Day 2) |
|---|-------|----------|-------------|
| G1 | 261,831 exact duplicate rows (26.2%) | Critical | drop_duplicates() before any join |
| G2 | Lat/lon outside Brazil bounding box: 31 rows | Critical | Lat range found: -36.6 to 45.1, Lon range: -101.5 to 121.1. Fix: drop rows outside (-33.7 to 5.3 lat, -73.9 to -28.8 lon) |
| G3 | Multiple lat/lon per zip prefix (avg 52.6) | Medium | Aggregate: mean lat/lon per zip prefix |

---

## products (32,951 rows × 9 cols)

| # | Issue | Severity | Fix (Day 2) |
|---|-------|----------|-------------|
| PR1 | Dimension cols (weight, length, height, width): [TBD] nulls | Medium | Impute median per category |
| PR2 | 13 product categories have no English translation | Low | Manual map or label as "other" |

---

## Key Integrity

| # | Issue | Severity | Fix (Day 2) |
|---|-------|----------|-------------|
| K1 | 775 orders with no line items | Medium | Breakdown: 603 unavailable, 
164 cancelled, 5 created, 2 invoiced, 1 shipped. The shipped order 
(a68ce168...) has carrier_date populated but no customer delivery 
confirmation - consistent with lost-in-transit or unscanned delivery 
in 2016. Not a data integrity error. All 775 safely excluded from 
revenue analysis. |
| K2 | 1 order with no payment record | Low | Investigate order_id, likely data entry gap |

---

## What is NOT an issue

- Zero orphaned foreign keys across all tables means referential integrity is clean
- Zero nulls in orders.order_id, customer_id, order_status means core identifiers intact  
- payment_installments up to 24 as expected in Brazilian credit market
- 27 states including DF correct for Brazil
- Geolocation avg 52.6 rows per zip prefix by design, multiple coordinate readings per area

## Validated metrics 

- Late delivery rate (clean delivered orders): 6.7%
- Median days to deliver: 10 days
- Mean days to deliver: 12 days
- Reliable order base for SLA analysis: 96,193