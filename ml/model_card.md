# Model Card: Delivery Delay Prediction
**Project:** Olist Brazilian E-Commerce Analytics  
**Author:** Chandan Ram Saii G  
**Date:** May 2025  
**Model file:** `ml/models/rf_delivery_delay.pkl`  
**Training notebook:** `notebooks/06_ml_delivery_delay.ipynb`

---

## 1. Problem Statement

**Business question:** Can we predict, at the moment an order is placed, whether it will arrive late to the customer?

**Why this matters for Olist:**  
Late deliveries are the single largest driver of low review scores on the platform.
A seller with a 12.26% historical late rate earns an average review score of 3.35 —
well below the platform median. If Olist can flag high-risk orders before they ship,
it can intervene: alert the seller, adjust the estimated delivery date shown to the
customer, or prioritise routing. This is a proactive operational tool, not a
post-mortem report.

**Why classification, not regression:**  
The business intervention is binary — act on this order or don't. Predicting exact
delay days is less actionable than a probability score that triggers a flag. A
logistics operations team needs a ranked list of risky orders at the start of each
day, not a continuous delay estimate.

---

## 2. Target Variable

| Field | Detail |
|---|---|
| `is_late` | 1 if `order_delivered_customer_date > order_estimated_delivery_date`, else 0 |
| Base population | Delivered orders only — cancelled, unavailable, and in-progress orders excluded |
| Source view | `olist.v_delivery_delay_drivers` |
| SLA base (after null exclusion) | 96,178 orders |
| Late orders | 6,477 (6.73%) |
| On-time orders | 89,701 (93.27%) |
| Class ratio | ~14:1 (on-time to late) |

**Note:** The 6.73% late rate is computed on delivered orders only.
The platform's overall cancellation rate (1.24%) is analysed separately in
`v_cancellation_analysis` and is not conflated with delivery SLA here.

---

## 3. Data Loading and Null Handling

Data was loaded directly from the PostgreSQL view `olist.v_delivery_delay_drivers`
via SQLAlchemy. Two null decisions were made before the feature matrix was built:

### `approval_lag_hours` — 14 rows dropped
Excluded at the SQL layer via `WHERE approval_lag_hours IS NOT NULL`.
14 rows represents 0.015% of the dataset. Dropping was preferred over imputation
because `approval_lag_hours` is a seller behaviour signal — imputing a median
would misrepresent seller responsiveness for those orders. Impact on class
distribution is negligible.

### `primary_category` — 1,325 rows imputed as `'unknown'`
1,325 orders (1.4% of dataset) had no product category mapped.  
Late rate for null-category orders: **7.09%**  
Late rate for categorised orders: **6.73%**  
Difference is small (0.36 percentage points). Dropping was rejected because in
production, uncategorised orders will continue to arrive — the model must handle
them without special casing. Imputing `'unknown'` as a distinct category before
label encoding means the model learns a behaviour for uncategorised orders rather
than failing at inference time.

### Final dataset entering model pipeline
After both decisions:

| Metric | Value |
|---|---|
| Total rows | 96,178 |
| Null values in any feature | 0 (confirmed) |
| Late rate | 6.73% |

---

## 4. Features

16 features, all derived from data available **at order placement time**.
No post-delivery information is included.

| # | Feature | Type | Source | Business Rationale |
|---|---|---|---|---|
| 1 | `seller_hist_late_rate` | float | Seller history (global avg) | **Top predictor (0.300).** A seller's past late delivery rate is the strongest available signal of future delay risk. |
| 2 | `order_month_num` | int | orders table | **Second predictor (0.162).** Month captures strong seasonality — November Black Friday peak (1.14M BRL revenue spike) causes systemic platform-wide delays. |
| 3 | `customer_state_enc` | int (label-encoded) | customers table | **0.077.** 27 Brazilian states with very different logistics infrastructure. Remote northern states face structurally longer transit times. |
| 4 | `seller_avg_days_to_deliver` | float | Seller history | **0.072.** Seller's historical average actual delivery time. Distinct from `estimated_delivery_days` (the platform's promise) — this captures actual operational pace. |
| 5 | `freight_value` | float | order_items | **0.066.** Higher freight = more distant or complex delivery route. |
| 6 | `seller_total_orders` | int | Seller history | **0.053.** Order volume proxy for seller capacity. High-volume sellers may face fulfilment bottlenecks; very low-volume sellers have unpredictable behaviour. |
| 7 | `approval_lag_hours` | float | orders table | **0.053.** Hours from customer purchase to seller approval. A seller who takes long to approve an order is more likely to be slow throughout fulfilment. |
| 8 | `freight_ratio_pct` | float | order_items | **0.039.** Freight as percentage of order value. High freight ratio signals remote delivery — derived feature, not raw. |
| 9 | `avg_product_volume_cm3` | float | products table | **0.035.** Average volume (length × height × width) across items in the order. Consolidated from three dimension columns to reduce multicollinearity. |
| 10 | `order_value` | float | order_items | **0.035.** Total order value. Higher value orders may involve slower or more careful fulfilment. |
| 11 | `avg_product_weight_g` | float | products table | **0.034.** Average product weight per order. Heavier shipments face more logistics friction and carrier constraints. |
| 12 | `order_hour` | int | orders table | **0.025.** Hour of day the order was placed. Orders placed late evening may miss same-day seller processing cutoffs. |
| 13 | `primary_category_enc` | int (label-encoded) | products table | **0.023.** 74 product categories + 'unknown'. Bulky categories (furniture, appliances) have structurally worse SLA. |
| 14 | `order_day_of_week` | int | orders table | **0.017.** Weekend orders may experience fulfilment delays if sellers don't operate on weekends. |
| 15 | `item_count` | int | order_items | **0.005.** Number of items in the order. Multi-item orders require all items to be ready before shipment. |
| 16 | `seller_count` | int | order_items | **0.003.** Number of distinct sellers in the order. Multi-seller orders depend on the slowest seller. |

### Feature engineering decisions

**`avg_product_volume_cm3`** — product dimensions (`product_length_cm`,
`product_height_cm`, `product_width_cm`) were consolidated into a single volume
feature (length × height × width). The three raw columns were correlated with each
other and carried redundant information. A single volume measure reduces
dimensionality without losing signal.

**`freight_ratio_pct`** — derived as `freight_value / order_value`. Captures the
relative cost of delivery, not just absolute freight, which varies significantly
by order size.

### Feature dropped during development

**`avg_item_price`** — Pearson r = 0.933 with `order_value`. Multicollinearity
confirmed in `notebooks/04_eda.ipynb` Chart 9. Dropped; `order_value` retained
as the more interpretable feature.

---

## 5. Model Choice Rationale

**Model selected: Random Forest (`sklearn.ensemble.RandomForestClassifier`)**

Two models were evaluated on identical features and split:

| Model | AUC-ROC | Late Recall | Late Precision | Late F1 |
|---|---|---|---|---|
| Logistic Regression (baseline) | 0.7223 | — | — | — |
| **Random Forest (final)** | **0.8031** | **0.5799** | **0.2200** | **0.3190** |

**Why Random Forest over Logistic Regression:**
- AUC improvement of +8.1 percentage points on the same feature set
- Handles non-linear interactions without manual feature engineering — for example,
  the combination of high `seller_hist_late_rate` and high `order_month_num`
  (November) likely compounds delay risk in a way a linear model cannot capture
- Feature importance output (Mean Decrease in Impurity) gives an interpretable
  signal to Olist's operations team — not just a prediction, but a reason

**Why not XGBoost or LightGBM:**  
Random Forest at AUC=0.80 with transparent feature importance is more defensible
in a business setting than a marginally better gradient boosted ensemble that
requires more explanation. If this were a production system, XGBoost would be the
next candidate with full hyperparameter tuning. That is documented as a future
improvement, not a gap.

**Why not a time series model:**  
The prediction target is per-order, not an aggregate trend. Each order is
classified independently based on features available at placement time.

---

## 6. Hyperparameters

| Parameter | Value | Rationale |
|---|---|---|
| `n_estimators` | 300 | Stability over 100-tree default without excessive compute |
| `max_depth` | 12 | Prevents overfitting on 76,942 training rows |
| `min_samples_leaf` | 20 | Smooths leaf-level predictions — important with 14:1 class imbalance |
| `max_features` | `'sqrt'` | sklearn default for classification; reduces correlation between trees |
| `class_weight` | `'balanced'` | Handles 14:1 imbalance — see Section 7 |
| `criterion` | `'gini'` | sklearn default |
| `bootstrap` | `True` | sklearn default |
| `n_jobs` | `-1` | All available cores |
| `random_state` | 42 | Reproducibility |

Full grid search was not performed. Parameters were set based on standard practice
for imbalanced classification on tabular data of this size. This is documented as
a limitation — see Section 10.

---

## 7. Class Imbalance Handling

| Item | Detail |
|---|---|
| Class distribution | 93.27% on-time / 6.73% late |
| Ratio | ~14:1 |
| Method | `class_weight='balanced'` |
| Effect | Scales each class's loss contribution inversely proportional to its frequency. The minority class (late) receives ~14× the weight of the majority class during training. |

**Why not SMOTE:**  
SMOTE synthesises new minority-class samples in feature space. For this dataset,
several features are business-derived aggregates (`seller_hist_late_rate`,
`seller_avg_days_to_deliver`) that represent real seller histories — synthesising
new rows risks producing seller profiles that don't exist. `class_weight='balanced'`
achieves similar effect without creating artificial data, and avoids any risk of
data leakage from oversampling before the train/test split.

---

## 8. Train / Test Split

| Parameter | Value |
|---|---|
| Method | `train_test_split`, stratified on `is_late` |
| Train rows | 76,942 (80%) |
| Test rows | 19,236 (20%) |
| Train late rate | 6.73% |
| Test late rate | 6.73% |
| `random_state` | 42 |

Stratification ensured identical class proportions in both sets.

**Known limitation — no temporal split:** A random stratified split was used
instead of a time-based split. In production, training on earlier orders and
testing on later ones is mandatory to prevent implicit temporal leakage. This is
the first change required before any real deployment — see Section 10, Limitation 1.

---

## 9. Results

### Classification Report (Test Set — 19,236 rows, Threshold = 0.50)

| Class | Precision | Recall | F1 | Support |
|---|---|---|---|---|
| On-time (0) | 0.9656 | 0.8516 | 0.9050 | 17,941 |
| Late (1) | 0.2200 | 0.5799 | 0.3190 | 1,295 |
| **AUC-ROC** | | | **0.8031** | |
| Accuracy | | | 0.8333 | 19,236 |

### Threshold Discussion

**Threshold used: 0.50**

The optimal threshold by late-class F1 was 0.6161. Threshold 0.50 was chosen
deliberately.

**Rationale:**  
In this business context, the cost asymmetry favours higher recall over higher
precision:
- **False negative** (missed late order): Customer receives a delayed order with
  no proactive communication. Damages trust, lowers review score, risks losing
  the customer. High cost.
- **False positive** (unnecessary alert): Olist flags a seller for an order that
  arrives on time. Seller receives an unneeded alert. Low cost.

At threshold 0.50, the model catches **57.99% of actual late orders** (580 out of
every 1,000 late orders flagged before delivery). At threshold 0.6161, precision
improves but recall drops — more late orders are missed.

For an operational early-warning tool where intervention cost is low, 0.50 is the
appropriate choice. If alert fatigue becomes a concern for seller relations, the
threshold would be revisited toward 0.55–0.60.

### Feature Importances (Mean Decrease in Impurity)

| Rank | Feature | Importance |
|---|---|---|
| 1 | `seller_hist_late_rate` | 0.300 |
| 2 | `order_month_num` | 0.162 |
| 3 | `customer_state_enc` | 0.077 |
| 4 | `seller_avg_days_to_deliver` | 0.072 |
| 5 | `freight_value` | 0.066 |
| 6 | `seller_total_orders` | 0.053 |
| 7 | `approval_lag_hours` | 0.053 |
| 8 | `freight_ratio_pct` | 0.039 |
| 9 | `avg_product_volume_cm3` | 0.035 |
| 10 | `order_value` | 0.035 |
| 11 | `avg_product_weight_g` | 0.034 |
| 12 | `order_hour` | 0.025 |
| 13 | `primary_category_enc` | 0.023 |
| 14 | `order_day_of_week` | 0.017 |
| 15 | `item_count` | 0.005 |
| 16 | `seller_count` | 0.003 |

**Key business interpretation:**  
`seller_hist_late_rate` at 0.300 — nearly double the next feature — confirms that
who the seller is matters more than what is being shipped or where it is going.
`order_month_num` at 0.162 confirms that systemic seasonal pressure (Black Friday,
year-end) is a structural delay driver independent of any individual seller.
Together these two features account for 46.2% of total model importance.

---

## 10. Limitations

**1. No temporal split — highest priority production fix**  
A stratified random split was used. The test set contains orders from all time
periods including late 2018, mixed with training data. For a production model,
training must occur on earlier orders with testing strictly on later orders.
A time-based split (e.g., train through March 2018, test April–August 2018) is
the first change required before deployment.

**2. `seller_hist_late_rate` computed on full dataset — look-ahead bias**  
This feature was computed as a global average across all orders for each seller,
then used as a training feature. This means when the model "predicts" an order
from January 2017, `seller_hist_late_rate` includes that seller's orders from
June 2018 — information that did not exist at prediction time. In production, this
feature must be computed as a rolling pre-order window: for each order, only orders
placed before that order's `order_purchase_timestamp` are used. Fixing this
requires recomputing the feature before retraining.

**3. Late recall of 57.99% — 42% of late orders are missed**  
The model is useful as a risk-scoring and prioritisation tool, not as a complete
detection system. At threshold 0.50, roughly 4 in 10 late orders will not be
flagged. It should be used to rank and prioritise intervention, not as a binary
gate.

**4. Late precision of 22% — most flagged orders arrive on time**  
Of every 100 orders flagged as high-risk, approximately 78 will arrive on time.
This is an acceptable tradeoff given low intervention cost, but must be communicated
clearly to operations teams to avoid alert fatigue.

**5. No hyperparameter grid search**  
Parameters were set by domain reasoning and standard practice for imbalanced
tabular classification. A grid search or Bayesian optimisation may improve AUC.
XGBoost with tuning is the recommended next step.

**6. Single time period, single market**  
Model trained on September 2016 – August 2018 Brazilian e-commerce data.
Generalisation to other markets, other time periods, or post-pandemic logistics
behaviour is not validated.

---

## 11. Artefacts

| File | Description |
|---|---|
| `ml/models/rf_delivery_delay.pkl` | Trained Random Forest (300 trees, scikit-learn 1.7.2, Python 3.13) |
| `ml/models/lr_scaler.pkl` | StandardScaler used for Logistic Regression baseline |
| `ml/models/le_customer_state.pkl` | LabelEncoder — 27 Brazilian states |
| `ml/models/le_primary_category.pkl` | LabelEncoder — 74 categories + `'unknown'` |
| `ml/models/feature_list.json` | 16 features in exact inference order |
| `notebooks/06_ml_delivery_delay.ipynb` | Full training code, evaluation, all charts |
| `reports/figures/chart10_threshold_tuning.png` | Threshold vs precision/recall curve |
| `reports/figures/chart11_model_evaluation.png` | ROC curve, confusion matrix |
| `reports/figures/chart12_feature_importance.png` | Feature importance bar chart |

---

## 12. How to Run Inference

```python
import pickle, json
import pandas as pd

# Load artefacts
with open('ml/models/rf_delivery_delay.pkl', 'rb') as f:
    model = pickle.load(f)
with open('ml/models/le_customer_state.pkl', 'rb') as f:
    le_state = pickle.load(f)
with open('ml/models/le_primary_category.pkl', 'rb') as f:
    le_category = pickle.load(f)
with open('ml/models/feature_list.json') as f:
    feature_list = json.load(f)

# feature_list order (must match exactly):
# ['order_day_of_week', 'order_hour', 'order_month_num', 'item_count',
#  'seller_count', 'order_value', 'freight_value', 'freight_ratio_pct',
#  'avg_product_weight_g', 'avg_product_volume_cm3', 'seller_hist_late_rate',
#  'seller_avg_days_to_deliver', 'seller_total_orders', 'approval_lag_hours',
#  'customer_state_enc', 'primary_category_enc']

# Encode categorical columns
# Handle unseen categories for primary_category with 'unknown'
X_new['customer_state_enc'] = le_state.transform(X_new['customer_state'])
X_new['primary_category_enc'] = le_category.transform(
    X_new['primary_category'].fillna('unknown')
)

# Predict
prob = model.predict_proba(X_new[feature_list])[:, 1]
flag = (prob >= 0.50).astype(int)  # 1 = high delay risk
```

**Environment requirement:** scikit-learn 1.7.2, Python 3.13. The pkl will not
load on earlier scikit-learn versions due to internal module path changes in 1.7.x.

---

## 13. Known Production Requirements Before Deployment

1. Recompute `seller_hist_late_rate` as a rolling pre-order window (no look-ahead)
2. Retrain on strict temporal split (train earlier, test later)
3. Add monitoring for `seller_hist_late_rate` distribution shift — if seller
   composition changes significantly, model performance will degrade
4. Handle label encoder unseen categories gracefully — wrap in try/except or use
   OrdinalEncoder with `handle_unknown='use_encoded_value'`
5. Retrain periodically as new seller behaviour data accumulates

---
