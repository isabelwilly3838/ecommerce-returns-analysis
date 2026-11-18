-- 02_return_rate_overview.sql
-- Goal: find which segment returns the most, and whether the gap is real or noise.
--
-- Return rate = returned items / delivered items, where "delivered" means the item reached
-- the customer (status 'Complete' or 'Returned'). Cancelled and in-transit items are excluded.
--
-- z_score compares each segment with the overall rate:
--   z = (segment_rate - overall_rate) / sqrt(overall_rate * (1 - overall_rate) / segment_items)
-- |z| > 2 is roughly "unlikely to be chance" (95%). |z| < 2 means treat the gap as noise.
-- A large z with a tiny gap is real but may not be worth fixing: look at returned_revenue too.

-- 1. Overall baseline
WITH delivered AS (
  SELECT
    oi.id,
    oi.sale_price,
    oi.status = 'Returned' AS is_returned
  FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
  WHERE oi.status IN ('Complete', 'Returned')
    AND oi.created_at < CURRENT_TIMESTAMP()
)
SELECT
  COUNT(*)                                          AS items_delivered,
  COUNTIF(is_returned)                              AS items_returned,
  ROUND(100 * AVG(IF(is_returned, 1, 0)), 2)        AS return_rate_pct,
  ROUND(SUM(sale_price), 0)                         AS revenue,
  ROUND(SUM(IF(is_returned, sale_price, 0)), 0)     AS returned_revenue
FROM delivered;

-- 2. By category (the main ranking)
WITH delivered AS (
  SELECT
    p.category,
    oi.sale_price,
    oi.status = 'Returned' AS is_returned
  FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
  JOIN `bigquery-public-data.thelook_ecommerce.products` p ON p.id = oi.product_id
  WHERE oi.status IN ('Complete', 'Returned')
    AND oi.created_at < CURRENT_TIMESTAMP()
),
by_segment AS (
  SELECT
    category                                       AS segment,
    COUNT(*)                                       AS items_delivered,
    COUNTIF(is_returned)                           AS items_returned,
    SAFE_DIVIDE(COUNTIF(is_returned), COUNT(*))    AS return_rate,
    SUM(IF(is_returned, sale_price, 0))            AS returned_revenue
  FROM delivered
  GROUP BY category
),
with_overall AS (
  SELECT
    *,
    SUM(items_returned) OVER () / SUM(items_delivered) OVER () AS overall_rate
  FROM by_segment
)
SELECT
  segment,
  items_delivered,
  items_returned,
  ROUND(100 * return_rate, 2)                                   AS return_rate_pct,
  ROUND(100 * (return_rate - overall_rate), 2)                  AS gap_vs_overall_pp,
  ROUND((return_rate - overall_rate)
        / SQRT(overall_rate * (1 - overall_rate) / items_delivered), 2) AS z_score,
  ROUND(returned_revenue, 0)                                    AS returned_revenue,
  ROUND(100 * returned_revenue / SUM(returned_revenue) OVER (), 1) AS pct_of_all_returned_revenue,
  RANK() OVER (ORDER BY return_rate DESC)                       AS rank_by_rate,
  RANK() OVER (ORDER BY returned_revenue DESC)                  AS rank_by_returned_revenue
FROM with_overall
ORDER BY return_rate DESC;

-- 3. By department, distribution centre and traffic source, in one result.
--    Same metrics, one row per (dimension, segment). Compare z-scores across dimensions:
--    the dimension with the largest |z| values is where the variation lives.
WITH delivered AS (
  SELECT
    p.department,
    dc.name               AS distribution_centre,
    u.traffic_source,
    oi.sale_price,
    oi.status = 'Returned' AS is_returned
  FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
  JOIN `bigquery-public-data.thelook_ecommerce.products` p              ON p.id = oi.product_id
  JOIN `bigquery-public-data.thelook_ecommerce.distribution_centers` dc ON dc.id = p.distribution_center_id
  JOIN `bigquery-public-data.thelook_ecommerce.users` u                 ON u.id = oi.user_id
  WHERE oi.status IN ('Complete', 'Returned')
    AND oi.created_at < CURRENT_TIMESTAMP()
),
long_format AS (
  SELECT 'department' AS dimension, department AS segment, sale_price, is_returned FROM delivered
  UNION ALL
  SELECT 'distribution_centre', distribution_centre, sale_price, is_returned FROM delivered
  UNION ALL
  SELECT 'traffic_source', traffic_source, sale_price, is_returned FROM delivered
),
by_segment AS (
  SELECT
    dimension,
    segment,
    COUNT(*)                                    AS items_delivered,
    COUNTIF(is_returned)                        AS items_returned,
    SAFE_DIVIDE(COUNTIF(is_returned), COUNT(*)) AS return_rate,
    SUM(IF(is_returned, sale_price, 0))         AS returned_revenue
  FROM long_format
  GROUP BY dimension, segment
),
with_overall AS (
  SELECT
    *,
    SUM(items_returned) OVER (PARTITION BY dimension)
      / SUM(items_delivered) OVER (PARTITION BY dimension) AS overall_rate
  FROM by_segment
)
SELECT
  dimension,
  segment,
  items_delivered,
  items_returned,
  ROUND(100 * return_rate, 2)                                   AS return_rate_pct,
  ROUND(100 * (return_rate - overall_rate), 2)                  AS gap_vs_overall_pp,
  ROUND((return_rate - overall_rate)
        / SQRT(overall_rate * (1 - overall_rate) / items_delivered), 2) AS z_score,
  ROUND(returned_revenue, 0)                                    AS returned_revenue
FROM with_overall
ORDER BY dimension, return_rate DESC;

-- 4. Category x department: does a category look bad only because of one department?
WITH delivered AS (
  SELECT
    p.category,
    p.department,
    oi.status = 'Returned' AS is_returned
  FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
  JOIN `bigquery-public-data.thelook_ecommerce.products` p ON p.id = oi.product_id
  WHERE oi.status IN ('Complete', 'Returned')
    AND oi.created_at < CURRENT_TIMESTAMP()
)
SELECT
  category,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(is_returned AND department = 'Women'), COUNTIF(department = 'Women')), 2) AS women_return_rate_pct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(is_returned AND department = 'Men'),   COUNTIF(department = 'Men')),   2) AS men_return_rate_pct,
  COUNTIF(department = 'Women') AS women_items,
  COUNTIF(department = 'Men')   AS men_items
FROM delivered
GROUP BY category
ORDER BY category;
