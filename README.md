# Olist Brazilian E-Commerce Analytics

![Python](https://img.shields.io/badge/Python-3.13-blue) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-blue) ![Tableau](https://img.shields.io/badge/Tableau-Public-orange) ![Looker](https://img.shields.io/badge/Looker-Studio-blue) ![Excel](https://img.shields.io/badge/Excel-Deliverable-green) ![ML](https://img.shields.io/badge/ML-scikit--learn-orange) ![Status](https://img.shields.io/badge/Status-Complete-green)

> An end-to-end data analytics project analyzing 1.55 million rows of Brazilian e-commerce data across the full order lifecycle from customer acquisition to delivery, cancellation, and seller performance.

---

## Project Overview

This is my second portfolio project, built during a career break after 4 years at Cognizant working on BFSI analytics. I chose the Olist dataset specifically because it is genuinely messy. Nine CSV files, Portuguese category names that needed translation, timezone inconsistencies, null cascades across joined tables, and a mixed percentage scale bug in an aggregated export that took real debugging to find and fix.

The most interesting technical decision I made was building a single denormalised CSV called unified_tableau.csv that combined RFM scores, order data, delivery metrics, and category SLA stats into one 110,197 row file to power the entire Tableau executive dashboard from a single source. What I did not expect was how badly Tableau misreads a CSV when the first column contains UUID strings. It was silently mapping columns to wrong positions, showing UUID hashes in the Segment column instead of names like Champions. The fix was re-exporting with explicit quoting and utf-8-sig encoding. The data was clean in Python. The problem was entirely in how the tool ingested it.

I also fixed a specific gap from Project 1 where Excel was missing as a deliverable. This project has Excel as a primary analytical deliverable.

Domain: E-Commerce (Brazil) | Scale: 1.55 million rows, 9 source files | Period: August 2016 to August 2018

---

## Business Questions Answered

| # | Business Question | Insight |
|---|---|---|
| 1 | Which customer segments drive the most revenue? | Champions at 23,413 customers lead revenue. Lost segment at 11,741 is nearly equal to Loyal Customers at 11,652, a near 1:1 churn to loyalty ratio |
| 2 | What is the cohort retention trend month over month? | Month 1 retention drops to 0.3 to 0.4 percent across all cohorts. Olist customers were largely one-time buyers during this period |
| 3 | Which product categories underperform on delivery SLA? | 6.73 percent overall late rate. Furniture and mattress categories exceed 13 percent late rate, driven by logistics complexity of bulky items |
| 4 | What drives order cancellations? | 625 cancellations total. DVDs and construction tools have highest category cancel rates. March 2017 and August 2018 show notable spikes |
| 5 | What is the revenue trend by category? | Total revenue 15.4 million BRL. November 2017 peak at 1,137,527 BRL likely driven by Black Friday. Health and beauty is the top revenue category |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Data Profiling and Cleaning | Python 3.13, pandas, numpy |
| Database | PostgreSQL 18 with star schema |
| SQL Analytics | 6 PostgreSQL views with pre-aggregated CTEs |
| Excel Deliverable | Power Query, pivot tables, dynamic charts, slicers |
| Executive Dashboard | Tableau Public (4 sheets, cross-sheet filter actions) |
| Operational Dashboard | Looker Studio (2 pages, 6 chart types) |
| Machine Learning | scikit-learn, Random Forest classifier |
| Version Control | Git and GitHub |
| IDE | VS Code with SQLTools |

---

## Architecture

```
9 Olist CSV files (data/raw/)
        |
  Python profiling and cleaning
  (nulls, duplicates, type casting,
   timezone conversion, translation)
        |
  PostgreSQL 18
  (star schema, 6 views)
        |
  Python EDA
  (10 charts, business findings)
        |
  Three dashboard layers:
  Excel (standalone deliverable)
  Tableau Public (executive)
  Looker Studio (operational)
        |
  ML: Random Forest
  (delivery delay prediction)
```

---

## Dataset

Source: Olist Brazilian E-Commerce on Kaggle
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

| File | Rows | Description |
|------|------|-------------|
| olist_orders_dataset.csv | 99,441 | Core fact table with order status and timestamps |
| olist_order_items_dataset.csv | 112,650 | Line items with price, freight, seller |
| olist_customers_dataset.csv | 99,441 | Customer location and unique ID |
| olist_sellers_dataset.csv | 3,095 | Seller city and state |
| olist_products_dataset.csv | 32,951 | Product catalog with category |
| olist_order_payments_dataset.csv | 103,886 | Payment type and installments |
| olist_order_reviews_dataset.csv | 99,224 | Review scores and comments |
| olist_geolocation_dataset.csv | 1,000,163 | ZIP level latitude and longitude |
| product_category_name_translation.csv | 71 | Portuguese to English category mapping |

---

## Data Quality Issues Found and Fixed

I profiled every file before touching anything. Here are the issues I documented with before and after for each.

| Issue | File | Before | After |
|-------|------|--------|-------|
| Missing product category names | order_items and products | 2,965 nulls | Filled with unknown_category |
| Timezone inconsistency in timestamps | orders | Mixed UTC offsets | Converted all to UTC |
| Duplicate geolocation entries | geolocation | 261,831 duplicates | Kept first occurrence per zip code |
| Mixed percentage scales in cohort export | cohort_retention.csv | Period 0 stored as 100.0, others as 0.34 | Normalised all to 0 to 1 scale |
| Null delivery dates on delivered orders | orders | 326 nulls | Excluded from SLA calculations, flagged separately |
| Category names in Portuguese | products | Portuguese strings | Joined with translation CSV for all dashboard exports |

---

## PostgreSQL Views

All views use pre-aggregated CTEs to avoid fan-out join errors, the same pattern I learned was critical in Project 1.

| View | Purpose |
|------|---------|
| v_rfm_segments | RFM scores and segment labels per customer |
| v_cohort_retention | Month over month retention rates by cohort |
| v_category_sla | Late rate and delivery days by product category |
| v_seller_performance | Seller KPIs including late rate, revenue, review score |
| v_revenue_by_category | Monthly revenue trend by top categories |
| v_cancellation_analysis | Cancellation rates by state and product category |

---

## Dashboards

### Tableau Public: Executive Dashboard

Four sheets covering RFM segment overview, monthly revenue trend for top 5 categories, cohort retention heatmap, and category SLA performance. Cross-sheet filter actions let you click any RFM segment and watch revenue and SLA charts update for that cohort only.

The cohort retention heatmap uses a second data source (cohort_retention.csv) because the pre-aggregated retention rates cannot be derived from the unified row-level CSV. This is intentional and documented in the notebooks.

Link: https://public.tableau.com/app/profile/chandan.ram.saii.gedala/viz/Olist_Executive_Dashboard_17794772826570/ExecutiveDashboard

### Looker Studio: Operational Dashboard

Two pages. Page 1 covers seller SLA performance with three KPI scorecards, a top 20 sellers by late rate bar chart, and a scatter plot of order volume versus late rate. The scatter shows late deliveries are concentrated among low-volume sellers, not high-volume ones, which suggests a capacity issue rather than a systemic logistics failure.

Page 2 covers cancellation analysis with a monthly cancellation rate time series from January 2017 to August 2018, a top 15 categories by cancel rate bar chart with English names, and a state-level heatmap table.

Link: https://datastudio.google.com/reporting/de366546-6c60-4ab4-bb4b-16bed10660fc

### Excel Deliverable

Standalone analytical workbook built with Power Query for data ingestion, pivot tables for RFM and cohort summaries, dynamic charts for revenue trend and category performance, named ranges, conditional formatting, and slicers. Designed to be usable without any database connection.

File: excel/olist_analysis.xlsx

---

## ML Model: Delivery Delay Prediction

I built a Random Forest classifier to predict whether an order would be delivered late, framed as a binary classification problem. The business justification is straightforward: if you can flag an order as likely-late before it ships, you can prioritise it in the logistics queue or proactively notify the customer before they complain. Late deliveries are the single largest driver of low review scores on the platform. A seller with a 12.26 percent historical late rate earns an average review score of 3.35, well below the platform median.

I chose Random Forest over Logistic Regression because delivery delay is driven by non-linear interactions between seller history, product category, customer location, and seasonality. A linear model cannot capture the compounding effect of a high-risk seller shipping during the November Black Friday peak. Random Forest handles those interactions without manual feature engineering. I did not use XGBoost because Random Forest at AUC 0.8031 with transparent feature importance is more defensible in a business setting than a marginally better gradient boosted ensemble.

### Model Comparison

| Model | AUC-ROC | Late Recall | Late Precision | Late F1 |
|-------|---------|-------------|----------------|---------|
| Logistic Regression (baseline) | 0.7223 | n/a | n/a | n/a |
| Random Forest (final) | 0.8031 | 0.5799 | 0.2200 | 0.3190 |

The AUC improvement of 8.1 percentage points on identical features confirms non-linear interactions exist in the data.

### Classification Report (Test Set, 19,236 rows, Threshold 0.50)

| Class | Precision | Recall | F1 | Support |
|-------|-----------|--------|----|---------|
| On-time | 0.9656 | 0.8516 | 0.9050 | 17,941 |
| Late | 0.2200 | 0.5799 | 0.3190 | 1,295 |

At threshold 0.50 the model catches 57.99 percent of actual late orders before delivery. Late precision of 22 percent means roughly 78 of every 100 flagged orders will arrive on time. This is an acceptable tradeoff because the cost of a false positive (an unnecessary seller alert) is much lower than the cost of a false negative (a customer receiving a late order with no warning and leaving a low review score).

### Top 5 Features by Importance

| Rank | Feature | Importance | Business Meaning |
|------|---------|------------|-----------------|
| 1 | seller_hist_late_rate | 0.300 | Who the seller is matters more than what is being shipped |
| 2 | order_month_num | 0.162 | November Black Friday creates systemic platform-wide delays |
| 3 | customer_state_enc | 0.077 | Remote northern states face structurally longer transit times |
| 4 | seller_avg_days_to_deliver | 0.072 | Seller's actual historical delivery pace, not the platform promise |
| 5 | freight_value | 0.066 | Higher freight signals more distant or complex delivery route |

seller_hist_late_rate at 0.300 is nearly double the next feature. Who the seller is matters more than what is being shipped or where it is going. The top two features together account for 46.2 percent of total model importance.

Full documentation including all 16 features, hyperparameters, class imbalance handling, threshold rationale, known limitations, and inference code is in ml/model_card.md.

---

## Key Findings

### Customer Segmentation via RFM

I segmented 93,358 unique customers into 8 groups. Champions at 23,413 customers is the largest segment and accounts for a disproportionate share of revenue. What concerned me more was the near 1:1 ratio of Lost customers (11,741) to Loyal Customers (11,652). That tells me Olist had a retention problem during this period that was not being offset by loyalty programmes.

### Cohort Retention

Month 1 retention drops to 0.3 to 0.4 percent almost immediately across all cohorts. This is not a data error. It reflects the nature of Brazilian e-commerce in 2016 to 2018, where the platform was still building repeat purchase behaviour. The December 2017 cohort showed slightly better retention, likely driven by holiday gifting creating natural repeat purchase occasions.

The more pointed observation is that Olist was acquiring customers faster than it could retain them. The Lost segment at 11,741 sitting nearly equal to Loyal Customers at 11,652 confirms this. Growth during this period was driven almost entirely by new customer acquisition rather than repeat purchases from existing ones.

What Olist should do about this: the retention intervention needs to happen in the first 30 days after a customer's first order, which is exactly where the cohort data shows the sharpest drop. A post-delivery email sequence offering a discount on a second purchase, triggered specifically for Champions and Potential Loyalists identified through RFM scoring, would be the highest-leverage starting point. Targeting the full customer base with retention campaigns would be wasteful. The RFM segmentation in this project exists precisely to make that targeting possible.

### Delivery SLA

6.73 percent of delivered orders arrived late. Furniture, mattress, and office furniture categories exceeded 13 percent late rate. These are bulky, logistics-heavy categories, which explains the pattern. The more useful finding is that high-volume sellers had much lower late rates than low-volume sellers, visible in the Looker Studio scatter plot.

### Cancellations

625 orders were cancelled over the full period. The monthly trend showed two notable spikes: March 2017 at 1.23 percent during early platform growth and August 2018 at 1.29 percent toward the end of the dataset. DVDs and construction tools had the highest category-level cancel rates. Sao Paulo state had the highest absolute cancellation volume at 619 orders, which is expected given it also has the highest order volume.

### Revenue Trend

Total revenue was 15.4 million BRL across the period. November 2017 was the clear peak at 1,137,527 BRL, almost certainly driven by Black Friday. The top 5 revenue categories were health and beauty, watches and gifts, bed bath and table, sports and leisure, and computers and accessories.

---

## Technical Issues Encountered and Resolved

### Tableau UUID column misalignment

Tableau was silently remapping columns when the first column contained UUID strings. The Segment column showed UUID hashes instead of segment names like Champions. Fix: re-exported the CSV with quoting=1 and utf-8-sig encoding using pandas, which forces explicit quoting around every field and adds a BOM that Tableau parses correctly.

### Cohort retention percentage scale inconsistency

Period 0 was stored as 100.0 while all subsequent periods were stored as decimals like 0.34. Tableau displayed 10,000 percent for period 0 after applying percentage formatting. Fix: normalised all values to a 0 to 1 scale in Python before re-exporting. This was a data generation bug from the SQL view that I caught only during Tableau visualisation.

### PostgreSQL database name mismatch

All notebooks referenced the database as olist but it was created as olist_ecommerce. Fix: queried pg_database to list actual database names and updated all connection strings.

### Looker Studio data source caching

After updating cancellation_analysis.csv with English category names and re-importing to Google Sheets, Looker Studio continued showing Portuguese names from cache. Refreshing via the Resource menu did not clear it. Fix: deleted the chart entirely and rebuilt from scratch to force a fresh data read.

### Geo map rendering failure in Looker Studio

Looker Studio filled map requires the location dimension to be explicitly typed as a Geo field. Brazilian state abbreviations like SP, RJ, and MG were not recognised automatically. Fix: replaced the geo map with a heatmap table, which is more readable for an operational dashboard and does not require special field typing.

---

## Skills Demonstrated

| Skill | Evidence |
|-------|---------|
| SQL | 6 views with CTEs, window functions, and pre-aggregation pattern to avoid fan-out joins |
| Python | pandas profiling, cleaning pipeline, EDA with matplotlib and seaborn |
| Data Modeling | Star schema in PostgreSQL with fact and dimension tables |
| Tableau | 4-sheet dashboard, dual data sources, cross-sheet filter actions, calculated fields |
| Looker Studio | 2-page operational dashboard, 6 chart types, data source blending |
| Excel | Power Query ingestion, pivot tables, dynamic charts, slicers, named ranges |
| Machine Learning | Random Forest classifier with business-justified model selection |
| Model Evaluation | ROC-AUC, confusion matrix, feature importance, class imbalance handling |
| Data Quality | Documented every issue with before and after for each fix |
| Data Storytelling | Business insights framed for both executive and operational audiences |

---

## How to Run

Prerequisites: Python 3.13 with Anaconda, PostgreSQL 18, VS Code with SQLTools extension.

```bash
git clone https://github.com/ChandanRamSaiiG21/ecommerce-retail-analysis
cd ecommerce-retail-analysis
pip install -r requirements.txt
```

Download the Olist dataset from Kaggle and place all 9 CSVs in data/raw/ before running. Then run notebooks in this order.

```
01_profiling.ipynb
02_cleaning.ipynb
03_load_postgres.ipynb
04_eda.ipynb
05_csv_exports.ipynb
06_ml_delivery_delay.ipynb
```

---

## Project Structure

```
ecommerce-retail-analysis/
├── data/
│   ├── raw/                        # Original 9 Kaggle CSVs
│   ├── cleaned/                    # Cleaned CSVs after Python processing
│   ├── tableau/                    # Unified CSV and cohort CSV for Tableau
│   └── looker/                     # Aggregated CSVs for Looker Studio
├── notebooks/
│   ├── 01_profiling.ipynb          # Shape, nulls, dtypes, value distributions
│   ├── 02_cleaning.ipynb           # All fixes with before and after documentation
│   ├── 03_load_postgres.ipynb      # Star schema creation and loading
│   ├── 04_eda.ipynb                # 10 EDA charts with business interpretation
│   ├── 05_csv_exports.ipynb        # SQL views and dashboard CSV exports
│   └── 06_ml_delivery_delay.ipynb  # Delivery delay prediction model
├── sql/
│   ├── schema/                     # Star schema DDL
│   ├── queries/                    # Ad hoc analytical queries
│   └── views/                      # 6 PostgreSQL views
├── ml/
│   └── model_card.md               # Model documentation with real numbers
├── excel/
│   └── olist_analysis.xlsx         # Standalone Excel deliverable
├── reports/                        # EDA charts saved as PNGs
└── README.md
```

---

## Author

Chandan Ram Saii Gedala

4 years of experience as Software Engineer in Data Analytics and BI at Cognizant in the BFSI domain. Currently building a data analytics portfolio during a career break.

GitHub: https://github.com/ChandanRamSaiiG21

Project 1: Insurance Policy Lifecycle Analysis
https://github.com/ChandanRamSaiiG21/insurance-policy-analysis