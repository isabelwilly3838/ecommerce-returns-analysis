# Metric definitions

Source table: `weekly_kpis` (from `sql/04_weekly_kpis.sql`). One row per week × department × category × traffic source.
All rates are computed from summed counts, **never averaged across rows**, so they stay correct at any level of the dashboard (week, category, total).

| KPI | Definition | Formula | Why it matters |
|---|---|---|---|
| Items delivered | Items that reached the customer (status Complete or Returned) | `SUM(items_delivered)` | The denominator for every rate; also shows whether a segment is big enough to matter |
| Items returned | Delivered items that came back | `SUM(items_returned)` | Volume of reverse-logistics work |
| **Return rate** | Share of delivered items that were returned | `SUM(items_returned) / SUM(items_delivered)` | The headline KPI: the problem this project is about |
| Return rate gap (pp) | Segment return rate minus overall return rate, in percentage points | `segment rate − overall rate` | Shows where the excess is; ranks segments fairly |
| Excess returns | Returns above what the overall rate would predict for that segment | `items_returned − overall rate × items_delivered` | Turns a rate gap into a count you can put a cost on |
| Revenue | Sales value of delivered items | `SUM(revenue)` | Context: a high rate on a tiny category matters less |
| Returned revenue | Sales value of returned items | `SUM(returned_revenue)` | Money that came back; the business-case starting point |
| Returned revenue share | Share of revenue that was returned | `SUM(returned_revenue) / SUM(revenue)` | Return rate weighted by price: catches expensive returns |
| Net gross margin | Margin on items that were kept | `SUM(net_gross_margin)` | What the business actually earns after returns |
| Avg days to deliver | Average days from order to delivery | `SUM(sum_days_to_deliver) / SUM(items_with_delivery_time)` (items with a negative delivery time are excluded) | Fulfilment-speed driver tested in `sql/03` |
| Week-over-week change (pp) | This week's return rate minus last week's | `rate(week) − rate(week − 1)` | Early warning: is it getting worse? |

## DAX measures (Power BI)

Load `weekly_kpis.csv`, name the table `weekly_kpis`, and add a date table if you want time intelligence. These measures cover the table above:

```dax
Items Delivered   = SUM ( weekly_kpis[items_delivered] )
Items Returned    = SUM ( weekly_kpis[items_returned] )
Return Rate       = DIVIDE ( [Items Returned], [Items Delivered] )
Revenue           = SUM ( weekly_kpis[revenue] )
Returned Revenue  = SUM ( weekly_kpis[returned_revenue] )
Returned Revenue Share = DIVIDE ( [Returned Revenue], [Revenue] )
Net Gross Margin  = SUM ( weekly_kpis[net_gross_margin] )
Avg Days to Deliver = DIVIDE ( SUM ( weekly_kpis[sum_days_to_deliver] ), SUM ( weekly_kpis[items_with_delivery_time] ) )

Overall Return Rate =
    CALCULATE ( [Return Rate], REMOVEFILTERS ( weekly_kpis[category], weekly_kpis[department], weekly_kpis[traffic_source] ) )

Return Rate Gap pp = ( [Return Rate] - [Overall Return Rate] ) * 100

Excess Returns = [Items Returned] - [Overall Return Rate] * [Items Delivered]

Return Rate Prior Week =
    VAR wk = MAX ( weekly_kpis[week_start] )
    RETURN CALCULATE ( [Return Rate], REMOVEFILTERS ( weekly_kpis[week_start] ), weekly_kpis[week_start] = wk - 7 )

WoW Change pp = ( [Return Rate] - [Return Rate Prior Week] ) * 100
```

## Suggested dashboard layout (one page)

1. **KPI cards (top row):** Return Rate, Items Returned, Returned Revenue, WoW Change pp
2. **Line chart:** Return Rate by `week_start`, with Overall Return Rate as a reference line
3. **Bar chart:** Return Rate Gap pp by category, sorted, so the worst segment stands out
4. **Matrix:** category × traffic_source with Return Rate, conditional formatting
5. **Slicers:** department, traffic_source, week range

Keep the dashboard to the question in the memo: if a chart does not help answer "what drives returns and what is fixing it worth", leave it out.
