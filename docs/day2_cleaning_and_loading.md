# Day 2: Data Cleaning and PostgreSQL Loading

## Objective
Fix every issue documented on Day 1 with a visible before/after for each fix. 
Load the cleaned data into a star schema in PostgreSQL. Verify every row count.

---

## Guiding Principle

Every cleaning step in 02_cleaning.ipynb follows this pattern:

    print("BEFORE:", ...)
    # fix
    print("AFTER:", ...)

No silent fixes. If you cannot show a measurable before and after, either the 
fix did not work or it was not needed.

---

## Step 1: Datetime Casting

Files affected: orders (5 columns), order_items (1 column), reviews (2 columns)

Why this matters: pandas reads all CSV columns as strings by default. Any 
time-based calculation (days to deliver, late delivery flag, cohort month) 
will fail or produce wrong results if the columns are still object dtype.

Code pattern used:
    pd.to_datetime(column, errors="coerce")

Why errors="coerce": if any value cannot be parsed as a datetime, it becomes 
NaT (not a time) instead of throwing an error. This lets you see how many 
values failed to parse in the after print. If the null count increases 
significantly after casting, there were unparseable strings in the column 
that need investigation.

Validation: null counts after casting matched Day 1 profiling null counts 
exactly. No new nulls were introduced by the casting step.

---

## Step 2: Geolocation Cleaning

Three sub-steps applied in sequence. Order matters.

### 2a: Drop exact duplicates
261,831 rows removed. These are rows where every column is identical to 
another row. No information is lost by removing them.

### 2b: Clip coordinates to Brazil bounding box
Bounding box: lat -33.75 to 5.27, lon -73.99 to -28.85
31 rows removed. Coordinates outside this box are physically impossible for 
Brazil. Keeping them would corrupt any map visualization and skew any 
geographic aggregation.

### 2c: Aggregate to one row per zip prefix
Method: median lat/lon, mode city and state.

Why median not mean for coordinates:
Mean is sensitive to outliers. If a zip prefix has 50 coordinate readings and 
2 of them are slightly off due to GPS error, median absorbs that noise. Mean 
would pull the centroid toward the outliers. For mapping purposes median gives 
a more accurate center point.

Why mode for city and state:
A zip prefix belongs to one city and one state. Mode returns the most frequent 
value, which handles cases where minor spelling variations exist across rows 
for the same zip prefix.

Result: 1,000,163 rows reduced to 19,011 rows, one per unique zip prefix.

---

## Step 3: Review Deduplication

814 review_ids appeared more than once, affecting 1,603 rows.

Investigation confirmed: same review_id, same text, same score, same 
timestamps, but two different order_ids. This is a system-level bug in 
Olist's review platform.

Fix: drop_duplicates on review_id, keep first occurrence.

Why keep first and not last:
Both occurrences have identical content so the choice does not affect any 
analytical result. Keeping first is the standard convention and is 
reproducible.

Why not keep both:
Keeping both would double-count these reviews in any sentiment analysis or 
average score calculation. A customer who gave a score of 1 would be counted 
twice, artificially pulling average scores down.

Result: 1,603 rows reduced to 98,410 unique reviews.

---

## Step 4: Payment Aggregation

103,886 payment rows aggregated to 99,437 order-level rows.

Why aggregate:
The star schema has one row per order in fact_orders. A payment bridge table 
with multiple rows per order would require a GROUP BY in every revenue query, 
adding complexity with no benefit since the analytical questions are all at 
the order level.

Columns created:
- payment_value: sum of all payment amounts for the order
- payment_installments: max installments across payment methods
- payment_type_primary: dominant payment method by frequency
- payment_type_count: number of distinct payment methods used

Why max for installments:
An order can be split across payment types. The maximum installment count 
represents the longest financing commitment the customer made for that order.

The 3 not_defined rows:
Removed before aggregation. These rows have no payment type information and 
cannot be categorized. 3 rows out of 103,886 is 0.003% of data. Removal has 
zero impact on any analysis.

---

## Step 5: Product Cleaning

### 5a: Join translation
Left join on product_category_name. Left join used so products without a 
category name are retained rather than dropped.

### 5b: Manual transliteration of 13 unmapped categories
These categories existed in the products file but had no entry in the 
translation file. Options considered:

Option A: label them "unknown" - rejected. These are readable Portuguese 
words. Labelling them unknown loses information and is intellectually lazy.

Option B: drop them - rejected. These are valid products. Dropping them 
would remove them from category performance analysis.

Option C: manual transliteration - chosen. Each category was transliterated 
to a descriptive English equivalent. This preserves the information and 
makes the category readable in English-language dashboards.

### 5c: Dimension null imputation using category median
Columns affected: weight_g, length_cm, height_cm, width_cm

Why category median not global median:
A book and a refrigerator should not share the same imputed dimensions. 
Category median estimates missing values from products with similar 
characteristics.

Why median not mean within category:
Median is more resistant to extreme values within a category. A category 
with mostly small products and one very large product would have a mean 
pulled toward the large product.

Fallback: global median used for any product in a category where all 
dimension values are null. This affected a very small number of products.

---

## Step 6: Orders Derived Columns

### has_items (boolean)
Flags the 775 ghost orders with no line items. These orders are valid business 
events but must be excluded from item-level and revenue analysis.

### has_payment (boolean)
Flags the 1 order with no payment record. Edge case, kept for completeness.

### days_to_deliver
Calculation: order_delivered_customer_date minus order_purchase_timestamp, 
expressed in days.

Validation performed:
- Negative values would indicate delivered before purchased. Zero found.
- Values over 180 days investigated individually.

### The placeholder delivery date discovery

During validation of days_to_deliver, 14 orders showed delivery times over 
180 days. Investigation of the raw timestamps revealed that 12 of these 14 
orders had an order_delivered_customer_date of exactly 2017-09-19, regardless 
of their purchase date.

Extended investigation found 285 total orders with this pattern:
- 282 orders with customer delivery date of 2017-09-19
- 3 orders with customer delivery date of 2018-09-19

The 2017 cohort had a median purchase date of September 7 2017, just 12 days 
before the delivery date. Some orders in this group were purchased in February 
2017, making the implied delivery time over 6 months.

Conclusion: September 19 is a system batch closure date. Olist's platform 
stamped all unconfirmed deliveries with this date when running a cleanup job. 
These are not real delivery dates.

Action taken:
- Flagged all 285 orders with has_placeholder_delivery_date = True
- Nulled days_to_deliver, days_vs_estimate, and is_late for these orders
- These orders are excluded from all SLA and delivery delay analysis

This is a Critical data quality finding. Using these dates would have 
corrupted the entire delivery performance analysis.

### days_vs_estimate
Calculation: order_delivered_customer_date minus order_estimated_delivery_date.
Negative means delivered early. Positive means delivered late.

### is_late (boolean)
True if days_vs_estimate > 0.

### approval_lag_hours
Time from purchase to payment approval in hours. Used as a feature in the 
delivery delay prediction model on Day 5.

---

## Validated Metrics After Cleaning

These are the numbers you cite in the README and defend in interviews.

- Late delivery rate (clean delivered orders): 6.7%
- Median days to deliver: 10 days
- Mean days to deliver: 12 days
- Reliable order base for SLA analysis: 96,193 orders
- Orders excluded due to placeholder delivery date: 285
- Orders excluded due to null delivery date (undelivered): 2,965

---

## PostgreSQL Schema Design

### Why a star schema?

Star schemas are optimized for analytical queries. The pattern of joining one 
fact table to multiple dimension tables with simple foreign key joins is 
faster and more readable than a normalized OLTP schema for the types of 
GROUP BY aggregations this project requires.

### Table classification rationale

fact_orders: central fact table. Every business question starts here.
fact_order_items: item-level fact table. Revenue, product, seller analysis.
dim_customers: customer attributes. RFM uses customer_unique_id from here.
dim_sellers: seller attributes. SLA analysis joins here.
dim_products: product attributes with English category names pre-joined.
dim_geolocation: one row per zip prefix, aggregated median coordinates.
bridge_payments: aggregated payment data, one row per order.
bridge_reviews: deduplicated reviews with has_comment flag.

### Why translation was joined at load time

Keeping translation as a separate table would require an extra join in every 
category-level query. Since the translation is static (it never changes), 
joining it once at load time and storing the English name in dim_products is 
the right design. It reduces query complexity with no downside.

### Index strategy

Indexes were created on:
- Every foreign key column (required for join performance)
- order_status (used in WHERE clauses constantly)
- order_purchase_timestamp (used for time-series queries)
- is_late (used in SLA filtering)
- customer_unique_id (used for RFM grouping)
- geolocation_state (used for geographic aggregation)

Indexes cost storage and slow down inserts but dramatically speed up the 
SELECT queries that drive all downstream analysis. For a read-heavy analytical 
workload this is always the right trade-off.

---

## Credential Management

Credentials stored in .env file using python-dotenv pattern.
.env is in .gitignore and was never committed to the repository.
.env.example committed with placeholder values so collaborators know what 
variables to set.

Why this matters: hardcoding passwords in notebooks is a security risk even 
in portfolio projects. Recruiters and interviewers do look at commit history. 
A leaked credential in a public repo is a red flag regardless of context.

Special character handling: password containing @ required url encoding via 
urllib.parse.quote_plus before building the SQLAlchemy connection string. 
The @ symbol in a URL-style connection string is interpreted as the separator 
between credentials and hostname without encoding.

---

## Row Count Verification

All 8 tables verified against expected row counts after loading.

| Table | Expected | Loaded | Match |
|---|---|---|---|
| dim_customers | 99,441 | 99,441 | OK |
| dim_sellers | 3,095 | 3,095 | OK |
| dim_products | 32,951 | 32,951 | OK |
| dim_geolocation | 19,011 | 19,011 | OK |
| fact_orders | 99,441 | 99,441 | OK |
| fact_order_items | 112,650 | 112,650 | OK |
| bridge_payments | 99,437 | 99,437 | OK |
| bridge_reviews | 98,410 | 98,410 | OK |

End-to-end join test confirmed: delivered orders returned highest revenue at 
15.4 million Brazilian reais across 96,477 orders.

---

## Issues Encountered and Resolved

### psycopg2 not found
Cause: notebook was using a different Anaconda environment than where 
psycopg2 was installed. Fixed by switching the VS Code kernel to the correct 
interpreter path.

### Password authentication failed
Cause: connection string still contained placeholder YOUR_PASSWORD text. 
Fixed by implementing dotenv pattern.

### Password with special character broke connection string
Cause: password contained @ symbol which is used as a delimiter in 
URL-style connection strings. Fixed by encoding password with 
urllib.parse.quote_plus before building the connection string.

### product_name_lenght column mismatch
Cause: original Olist CSV contains a typo in two column names 
(lenght instead of length). Schema DDL used correct spelling. 
Fixed by renaming columns in the dataframe before loading. 
CSV also updated to reflect corrected names.

### dim_geolocation loaded 0 rows silently
Cause: load step was skipped during an earlier failed run. The table 
existed but was empty. Fixed by running load_table for dim_geolocation 
directly and verifying the count immediately after.

---

## Interview Talking Points

"I validated every cleaning step with a before and after print. No silent 
fixes anywhere in the notebook."

"The placeholder delivery date finding came from investigating outliers rather 
than just capping or removing them. 285 orders had a batch system closure date 
of September 19 stamped as their delivery date. Using those dates would have 
made delivery performance look far worse than it actually was."

"I used category median for product dimension imputation rather than global 
median because products in the same category have similar physical 
characteristics. Global median would have been less accurate."

"The customer_id versus customer_unique_id distinction is critical for this 
dataset. All RFM and cohort analysis uses customer_unique_id as the person 
identifier. Using customer_id would make every customer appear to have 
purchased exactly once."

"I managed database credentials using python-dotenv. The .env file is in 
.gitignore and was never committed. I also handled a URL encoding issue caused 
by a special character in the password."