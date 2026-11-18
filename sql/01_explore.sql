-- 01_explore.sql
-- Goal: get to know the tables before measuring anything.
-- Dataset: bigquery-public-data.thelook_ecommerce (synthetic, refreshed daily)
-- Run each statement and write one line in the memo about what it tells you.

-- 1. How big is each table?
SELECT 'orders'               AS table_name, COUNT(*) AS row_count FROM `bigquery-public-data.thelook_ecommerce.orders`
UNION ALL SELECT 'order_items',          COUNT(*) FROM `bigquery-public-data.thelook_ecommerce.order_items`
UNION ALL SELECT 'products',             COUNT(*) FROM `bigquery-public-data.thelook_ecommerce.products`
UNION ALL SELECT 'users',                COUNT(*) FROM `bigquery-public-data.thelook_ecommerce.users`
UNION ALL SELECT 'distribution_centers', COUNT(*) FROM `bigquery-public-data.thelook_ecommerce.distribution_centers`
UNION ALL SELECT 'inventory_items',      COUNT(*) FROM `bigquery-public-data.thelook_ecommerce.inventory_items`
ORDER BY row_count DESC;

-- 2. What period does the data cover? (Check for future-dated rows: the generator creates some.)
SELECT
  MIN(created_at)                                    AS first_item_created,
  MAX(created_at)                                    AS last_item_created,
  COUNTIF(created_at > CURRENT_TIMESTAMP())          AS future_dated_items,
  COUNT(DISTINCT order_id)                           AS orders,
  COUNT(*)                                           AS items
FROM `bigquery-public-data.thelook_ecommerce.order_items`;

-- 3. Which item statuses exist, and how common is each?
--    Only 'Complete' and 'Returned' items have reached the customer, so they are the
--    denominator for the return rate. 'Cancelled', 'Processing' and 'Shipped' are excluded.
SELECT
  status,
  COUNT(*)                                           AS items,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_items
FROM `bigquery-public-data.thelook_ecommerce.order_items`
GROUP BY status
ORDER BY items DESC;

-- 4. Is the status consistent with the timestamps? (Decide which one to trust.)
SELECT
  status,
  COUNTIF(shipped_at   IS NOT NULL) AS has_shipped_at,
  COUNTIF(delivered_at IS NOT NULL) AS has_delivered_at,
  COUNTIF(returned_at  IS NOT NULL) AS has_returned_at,
  COUNT(*)                          AS items
FROM `bigquery-public-data.thelook_ecommerce.order_items`
GROUP BY status
ORDER BY items DESC;

-- 5. Do order-level and item-level statuses agree? (An order can have several items.)
SELECT
  o.status  AS order_status,
  oi.status AS item_status,
  COUNT(*)  AS items
FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
JOIN `bigquery-public-data.thelook_ecommerce.orders` o USING (order_id)
GROUP BY order_status, item_status
ORDER BY order_status, items DESC;

-- 6. What can we segment by? Categories, departments, brands, centres, channels.
SELECT
  COUNT(DISTINCT category)               AS categories,
  COUNT(DISTINCT department)             AS departments,
  COUNT(DISTINCT brand)                  AS brands,
  COUNT(DISTINCT distribution_center_id) AS distribution_centres,
  COUNTIF(category IS NULL)              AS null_category,
  COUNTIF(brand IS NULL)                 AS null_brand
FROM `bigquery-public-data.thelook_ecommerce.products`;

SELECT traffic_source, COUNT(*) AS users
FROM `bigquery-public-data.thelook_ecommerce.users`
GROUP BY traffic_source
ORDER BY users DESC;

-- 7. How long do deliveries and returns take? (Tells you how long the return window is,
--    which matters for 04: recent weeks have not had time to show their returns yet.)
SELECT
  APPROX_QUANTILES(TIMESTAMP_DIFF(delivered_at, created_at, HOUR) / 24, 4) AS days_order_to_delivery_quartiles,
  APPROX_QUANTILES(TIMESTAMP_DIFF(returned_at, delivered_at, HOUR) / 24, 4) AS days_delivery_to_return_quartiles,
  MAX(TIMESTAMP_DIFF(returned_at, delivered_at, HOUR) / 24)                 AS max_days_to_return
FROM `bigquery-public-data.thelook_ecommerce.order_items`
WHERE status IN ('Complete', 'Returned');
