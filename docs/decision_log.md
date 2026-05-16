# Key Technical Decisions

## Why customer_unique_id and not customer_id for RFM
The dataset has two customer identifiers. customer_id is order-scoped, meaning 
a returning customer gets a new customer_id for each order. customer_unique_id 
is the true person identifier. Using customer_id for RFM would make every 
customer appear to have purchased exactly once, destroying the frequency and 
recency signals entirely.

## Why 285 orders were excluded from SLA analysis
During delivery time validation, 285 delivered orders were found to have a 
customer delivery date of exactly 2017-09-19 or 2018-09-19 regardless of 
their actual purchase date. Orders purchased in February 2017 showed implied 
delivery times of over 6 months. This pattern is consistent with a system 
batch closure job that stamped unconfirmed deliveries with a placeholder date. 
These orders are flagged with has_placeholder_delivery_date = True and excluded 
from all delivery performance metrics.

Validated late delivery rate on clean orders: 6.7% across 96,193 orders.

## Why category median for product dimension imputation
Product dimension nulls were imputed using the median value within each 
product category rather than the global median. A book and a refrigerator 
should not share the same imputed weight. Category median estimates missing 
values from products with similar physical characteristics.

## Why payments were aggregated before loading
The raw payments table has multiple rows per order to support split payment 
methods. All analytical questions in this project operate at the order level. 
Aggregating to one row per order before loading eliminates the need for a 
GROUP BY in every revenue query and simplifies all downstream joins.

## Why geolocation was aggregated to zip prefix level
The raw geolocation table had 1,000,163 rows with an average of 52 coordinate 
readings per zip prefix after deduplication. Customers and sellers each have 
one zip prefix. Aggregating to one row per zip prefix using median coordinates 
reduced the table to 19,011 rows with no loss of information for this use case.

## Why translation was joined at load time
The product category translation is static. Joining it once at load time and 
storing the English name in dim_products reduces query complexity for every 
downstream category analysis without any downside.

## Why Random Forest for delivery delay prediction (Day 5)
Documented in ml/model_rationale.md