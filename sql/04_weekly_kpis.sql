-- 04_weekly_kpis.sql
-- Goal: one tidy table for Excel and Power BI.
-- Grain: one row per week x department x category x traffic source.
-- Export: Save results -> CSV (local file) -> excel/weekly_kpis.csv
--
-- Store counts and sums only, never pre-averaged rates, so every tool can re-aggregate
-- correctly (return rate = SUM(items_returned) / SUM(items_delivered), never AVG of rates).
--
-- Weeks are assigned by the date the item was ordered (cohort view). Recent weeks have not
-- had time to collect all their returns, so the last `maturity_days` are left out.
-- From 01, query 7: delivery takes up to ~8 days and returns come within ~3 days of
-- delivery, so every return is in by ~11 days after ordering. 14 days leaves a margin.

DECLARE weeks_back    INT64 DEFAULT 104;  -- two years keeps the CSV small (~15k rows)
DECLARE maturity_days INT64 DEFAULT 14;

WITH delivered AS (
  SELECT
    DATE_TRUNC(DATE(oi.created_at), WEEK(MONDAY))           AS week_start,
    p.department,
    p.category,
    u.traffic_source,
    oi.sale_price,
    p.cost,
    oi.status = 'Returned'                                  AS is_returned,
    -- negative delivery times (delivered before ordered) are a data quirk: treat as unknown
    IF(oi.delivered_at >= oi.created_at,
       TIMESTAMP_DIFF(oi.delivered_at, oi.created_at, HOUR) / 24, NULL) AS days_to_deliver
  FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
  JOIN `bigquery-public-data.thelook_ecommerce.products` p ON p.id = oi.product_id
  JOIN `bigquery-public-data.thelook_ecommerce.users` u    ON u.id = oi.user_id
  WHERE oi.status IN ('Complete', 'Returned')
)
SELECT
  week_start,
  department,
  category,
  traffic_source,
  COUNT(*)                                                  AS items_delivered,
  COUNTIF(is_returned)                                      AS items_returned,
  ROUND(SUM(sale_price), 2)                                 AS revenue,
  ROUND(SUM(IF(is_returned, sale_price, 0)), 2)             AS returned_revenue,
  ROUND(SUM(IF(is_returned, 0, sale_price - cost)), 2)      AS net_gross_margin,
  ROUND(SUM(days_to_deliver), 2)                            AS sum_days_to_deliver,
  COUNTIF(days_to_deliver IS NOT NULL)                      AS items_with_delivery_time
FROM delivered
WHERE week_start <  DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL maturity_days DAY), WEEK(MONDAY))
  AND week_start >= DATE_SUB(
        DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL maturity_days DAY), WEEK(MONDAY)),
        INTERVAL weeks_back WEEK)
GROUP BY week_start, department, category, traffic_source
ORDER BY week_start, department, category, traffic_source;
