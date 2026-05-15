# Profiling Summary & Schema Decision

## Key findings driving schema design

The orders table is the central fact table with 99,441 orders, clean 
primary key, joins cleanly to all other tables. Order_items is the 
revenue fact table (112,650 rows, zero nulls). Customers requires 
careful handling: customer_id is order-scoped (one per order) while 
customer_unique_id is the true person identifier and RFM must use 
customer_unique_id or we overcount unique customers by ~3,400.

Geolocation cannot be used raw (261,831 duplicates and 31 
out-of-bounds) coordinates must be cleaned first, then aggregated 
to one lat/lon per zip prefix before joining to customers or sellers.

Reviews will be used for score analysis only. Comment text dropped 
 - 88.3% null on title makes it unusable.

## Star schema decision

Fact tables: orders, order_items
Dimension tables: customers, sellers, products, geolocation (aggregated)
Bridge: payments (one-to-many per order), reviews (one-to-one per order)
Translation table joined to products at load time, not kept separate.