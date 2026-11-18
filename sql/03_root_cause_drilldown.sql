-- 03_root_cause_drilldown.sql
-- Goal: explain WHY the worst segment from 02 returns more. Test one hypothesis per query.
--
-- Set target_category to the worst category from 02 (exact spelling, e.g. 'Jeans').
-- Each query compares the target category with all other categories ("rest"), so you can
-- see whether a driver is specific to the target or affects everyone equally.
-- A driver you can defend shows: a clear gap, |z| > 2, and enough items to matter.

-- Chosen from 02: no category returns more often, but Outerwear & Coats carries the most
-- returned revenue (12.6%, ~$147 per returned item).
DECLARE target_category STRING DEFAULT 'Outerwear & Coats';
-- Ignore brands too small to trust. There are ~2,750 brands, so one category has only a few
-- thousand delivered items spread over hundreds of brands. If query 1 returns few or no rows,
-- lower this (not below ~30) and treat brand-level gaps with caution.
DECLARE min_items INT64 DEFAULT 50;

CREATE TEMP TABLE delivered AS
SELECT
  oi.id                                                   AS item_id,
  IF(p.category = target_category, 'target', 'rest')      AS grp,
  p.category,
  p.brand,
  p.retail_price,
  oi.sale_price,
  p.cost,
  dc.name                                                 AS distribution_centre,
  u.traffic_source,
  u.age,
  u.country,
  oi.created_at,
  -- Some items are "delivered" before they were ordered (a generator quirk, found in 01):
  -- treat those delivery times as unknown rather than negative.
  IF(oi.delivered_at >= oi.created_at,
     TIMESTAMP_DIFF(oi.delivered_at, oi.created_at, HOUR) / 24, NULL) AS days_to_deliver,
  TIMESTAMP_DIFF(oi.returned_at, oi.delivered_at, HOUR) / 24 AS days_to_return,
  oi.status = 'Returned'                                  AS is_returned
FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
JOIN `bigquery-public-data.thelook_ecommerce.products` p              ON p.id = oi.product_id
JOIN `bigquery-public-data.thelook_ecommerce.distribution_centers` dc ON dc.id = p.distribution_center_id
JOIN `bigquery-public-data.thelook_ecommerce.users` u                 ON u.id = oi.user_id
WHERE oi.status IN ('Complete', 'Returned')
  AND oi.created_at < CURRENT_TIMESTAMP();

-- 0. Confirm the starting gap
SELECT
  grp,
  COUNT(*)                                      AS items_delivered,
  ROUND(100 * AVG(IF(is_returned, 1, 0)), 2)    AS return_rate_pct
FROM delivered
GROUP BY grp;

-- 1. Brand: is it a few bad brands, or the whole category?
--    If the top 3 brands explain most of the excess returns, the fix is supplier-level.
WITH b AS (
  SELECT
    brand,
    COUNT(*)                                    AS items_delivered,
    COUNTIF(is_returned)                        AS items_returned,
    SUM(IF(is_returned, sale_price, 0))         AS returned_revenue
  FROM delivered
  WHERE grp = 'target'
  GROUP BY brand
  HAVING COUNT(*) >= min_items
),
cat AS (
  SELECT SUM(items_returned) / SUM(items_delivered) AS cat_rate FROM b
)
SELECT
  brand,
  items_delivered,
  ROUND(100 * items_returned / items_delivered, 2)                         AS return_rate_pct,
  ROUND((items_returned / items_delivered - cat_rate)
        / SQRT(cat_rate * (1 - cat_rate) / items_delivered), 2)             AS z_vs_category,
  -- "excess" returns = returns above what the category average would predict
  ROUND(items_returned - cat_rate * items_delivered, 0)                    AS excess_returns,
  ROUND(SUM(items_returned - cat_rate * items_delivered)
        OVER (ORDER BY items_returned / items_delivered DESC), 0)          AS cumulative_excess_returns,
  ROUND(returned_revenue, 0)                                               AS returned_revenue
FROM b CROSS JOIN cat
ORDER BY return_rate_pct DESC;

-- 2. Price band: do expensive (or cheap) items get returned more?
--    Quartiles are computed within each group, so "Q4" means "top 25% by price in that group".
WITH banded AS (
  SELECT
    *,
    NTILE(4) OVER (PARTITION BY grp ORDER BY sale_price) AS price_quartile
  FROM delivered
)
SELECT
  grp,
  CONCAT('Q', CAST(price_quartile AS STRING))   AS price_band,
  ROUND(MIN(sale_price), 2)                     AS min_price,
  ROUND(MAX(sale_price), 2)                     AS max_price,
  COUNT(*)                                      AS items_delivered,
  ROUND(100 * AVG(IF(is_returned, 1, 0)), 2)    AS return_rate_pct
FROM banded
GROUP BY grp, price_quartile
ORDER BY grp, price_quartile;

-- 3. Traffic source: do some channels bring customers who return more?
--    (Could point to misleading ads or poor targeting.)
SELECT
  traffic_source,
  COUNTIF(grp = 'target')                                                             AS target_items,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(grp = 'target' AND is_returned), COUNTIF(grp = 'target')), 2) AS target_return_rate_pct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(grp = 'rest' AND is_returned),   COUNTIF(grp = 'rest')),   2) AS rest_return_rate_pct
FROM delivered
GROUP BY traffic_source
ORDER BY target_return_rate_pct DESC;

-- 4. Delivery time: do slow deliveries lead to more returns?
SELECT
  grp,
  CASE
    WHEN days_to_deliver < 2 THEN '1. under 2 days'
    WHEN days_to_deliver < 4 THEN '2. 2-4 days'
    WHEN days_to_deliver < 6 THEN '3. 4-6 days'
    ELSE                          '4. 6+ days'
  END                                           AS delivery_band,
  COUNT(*)                                      AS items_delivered,
  ROUND(100 * AVG(IF(is_returned, 1, 0)), 2)    AS return_rate_pct
FROM delivered
WHERE days_to_deliver IS NOT NULL
GROUP BY grp, delivery_band
ORDER BY grp, delivery_band;

-- 5. Fulfilment path: does one distribution centre return more for the target category?
SELECT
  distribution_centre,
  COUNTIF(grp = 'target')                                                             AS target_items,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(grp = 'target' AND is_returned), COUNTIF(grp = 'target')), 2) AS target_return_rate_pct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(grp = 'rest' AND is_returned),   COUNTIF(grp = 'rest')),   2) AS rest_return_rate_pct,
  ROUND(AVG(IF(grp = 'target', days_to_deliver, NULL)), 2)                            AS target_avg_days_to_deliver
FROM delivered
GROUP BY distribution_centre
ORDER BY target_return_rate_pct DESC;

-- 6. Customer age band (fit problems often vary by age group)
SELECT
  grp,
  CASE
    WHEN age < 25 THEN '1. under 25'
    WHEN age < 35 THEN '2. 25-34'
    WHEN age < 50 THEN '3. 35-49'
    ELSE               '4. 50+'
  END                                           AS age_band,
  COUNT(*)                                      AS items_delivered,
  ROUND(100 * AVG(IF(is_returned, 1, 0)), 2)    AS return_rate_pct
FROM delivered
GROUP BY grp, age_band
ORDER BY grp, age_band;

-- 7. Discounting: are items sold below retail price returned more?
SELECT
  grp,
  IF(sale_price < retail_price, 'discounted', 'full price') AS pricing,
  COUNT(*)                                      AS items_delivered,
  ROUND(100 * AVG(IF(is_returned, 1, 0)), 2)    AS return_rate_pct
FROM delivered
GROUP BY grp, pricing
ORDER BY grp, pricing;

-- 8. Trend: is the problem getting worse, better, or stable? (quarterly)
SELECT
  DATE_TRUNC(DATE(created_at), QUARTER)         AS quarter,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(grp = 'target' AND is_returned), COUNTIF(grp = 'target')), 2) AS target_return_rate_pct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(grp = 'rest' AND is_returned),   COUNTIF(grp = 'rest')),   2) AS rest_return_rate_pct,
  COUNTIF(grp = 'target')                       AS target_items
FROM delivered
GROUP BY quarter
ORDER BY quarter;

-- 9. Cost of the problem: inputs for the memo's impact estimate.
--    excess_returns = returns above the "rest" rate. Multiply by your cost-per-return
--    assumption (stated and sourced in the memo) to size the opportunity.
WITH g AS (
  SELECT
    grp,
    COUNT(*)                                    AS items_delivered,
    COUNTIF(is_returned)                        AS items_returned,
    AVG(IF(is_returned, sale_price, NULL))      AS avg_returned_price,
    AVG(sale_price - cost)                      AS avg_unit_margin,
    DATE_DIFF(DATE(MAX(created_at)), DATE(MIN(created_at)), DAY) / 365.25 AS years_covered
  FROM delivered
  GROUP BY grp
)
SELECT
  t.items_delivered                                                     AS target_items_delivered,
  ROUND(100 * t.items_returned / t.items_delivered, 2)                  AS target_rate_pct,
  ROUND(100 * r.items_returned / r.items_delivered, 2)                  AS rest_rate_pct,
  ROUND(t.items_returned - t.items_delivered * r.items_returned / r.items_delivered, 0) AS excess_returns_total,
  ROUND((t.items_returned - t.items_delivered * r.items_returned / r.items_delivered)
        / t.years_covered, 0)                                           AS excess_returns_per_year,
  ROUND(t.avg_returned_price, 2)                                        AS avg_returned_item_price,
  ROUND(t.avg_unit_margin, 2)                                           AS avg_unit_margin,
  ROUND(t.years_covered, 2)                                             AS years_covered
FROM g t
JOIN g r ON t.grp = 'target' AND r.grp = 'rest';
