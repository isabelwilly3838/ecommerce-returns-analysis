# Business case: cutting the cost of returns

**Author:** Isabel Willy · **Data:** `bigquery-public-data.thelook_ecommerce`, queried 18 Nov 2026 · **Status:** final draft

## 1. Problem

Of 63,387 items delivered since January 2019, **18,265 were returned: a 28.8% return rate**,
worth about **$1.07M in returned revenue** (~$139k and ~2,370 returns a year). The commonly
quoted figure of 10% understates the problem almost threefold, because it divides by all
items, including cancelled and undelivered ones that could never have been returned.

The question was: which categories, channels or fulfilment paths drive returns, and what
would fixing the biggest driver be worth?

## 2. Root cause

**No single segment drives the return rate.** Returns sit at about 29% everywhere. I tested
six dimensions and none differs from the average by more than chance would explain:

| Dimension | Range of return rates | Verdict |
|---|---|---|
| Category (26) | 27.4% – 30.7% | No category clears the significance bar after correcting for 26 tests |
| Brand (within Outerwear) | 20.0% – 33.6% | No brand significant; the 7 worst explain only 22 extra returns out of ~918 |
| Price band | 28.4% – 29.9% | No trend |
| Distribution centre (10) | 27.9% – 29.6% | Not significant |
| Traffic source (5) | 28.0% – 29.0% | Not significant |
| Department | 28.8% vs 28.8% | Identical |

Two things *do* stand out:

1. **The cost of returns is concentrated, even though the rate is not.** Outerwear & Coats and
   Jeans return at average rates (29.3%, 28.8%) but account for **24% of all returned revenue**,
   because each return is worth $117 on average, against $59 across the catalogue.
2. **Slow delivery is the one lead.** Items delivered in 6+ days return at 30.0%, against 28.4%
   for items delivered in under 4 days (+1.6 pp, z ≈ 2.3), and the rate rises steadily with
   delivery time. Because many comparisons were made, I treat this as a hypothesis, not a proven cause.

The data cannot say **why** customers return: there is no return-reason field. That gap,
not a segment, is what blocks a true root cause.

## 3. Recommendation

1. **Add mandatory return-reason codes** (size/fit, damaged, arrived late, not as described,
   changed mind) to the returns flow. Owner: Returns / CX. Low cost, and the prerequisite for
   any confirmed root cause, including the delivery-speed lead.
2. **Prioritise return prevention by value, not by rate.** Start with Outerwear & Coats and
   Jeans, where each prevented return saves twice the average. Once reason codes show the
   main cause there (most likely fit), pilot the matching fix, e.g. a size guide.
3. **Do not fund faster shipping yet.** The effect is small and unconfirmed; revisit if
   reason codes show "arrived late" is a material share.
4. **Track it weekly** with the existing report and dashboard: return rate, returned revenue
   share, and return rate by delivery band.

## 4. Impact

Each 1 pp cut in return rate removes ~3.5% of returns. Annual value, from the data
(returned revenue retained; processing cost per return still to be added by finance):

| Lever | Assumption | Returns avoided / yr | Returned revenue retained / yr |
|---|---|---|---|
| Faster delivery for slow orders | 6+ day orders return at the under-4-day rate | ~12 | ~$700 |
| Fit fix on Outerwear & Jeans: low / base / high | rate falls by 1 / 3 / 5 pp | 10 / 29 / 49 | $1.1k / $3.4k / $5.7k |
| Catalogue-wide (for scale) | rate falls by 1 pp | ~82 | ~$4.8k |

The absolute numbers are small because this store is small (~8,200 delivered items a year).
In relative terms, a 3 pp cut on the two high-value categories retains ~2.5% of all returned
revenue, from 12% of delivered items.

## 5. Risks and limitations

- **Synthetic data:** `thelook_ecommerce` is generated. The method transfers; the numbers do not.
- **Correlation, not causation:** the delivery-time pattern needs reason codes or a test to confirm.
- **Too little volume to test quickly:** detecting a 1.6 pp effect with 80% power needs
  ~12,500 orders per group, which is years of slow orders here. At a large retailer it is weeks.
- **Whole-order returns:** every item in a returned order is marked returned, which blurs
  product-level differences (brand, category).
- **Return lag:** the weekly KPIs exclude the latest 14 days, until their returns are in.

## 6. Next steps

1. Agree the reason-code list with Returns / CX and add it to the returns form.
2. After 8 weeks of reason data, re-run the drill-down by reason for Outerwear and Jeans.
3. Add a delivery-band view to the weekly dashboard to keep watching the delivery lead.

---

## Appendix A: Evidence log

**From `01_explore`**
- Size: 180,764 order items across 124,780 orders (~1.45 items per order), 100,000 users,
  29,120 products, 10 distribution centres. The analysis works at item level.
- Period: 5 Jan 2019 to 21 Nov 2026. 1,583 items (0.9%) are dated in the future, a generator
  artefact, and are excluded (`created_at < CURRENT_TIMESTAMP()`).
- Statuses: Shipped 29.9%, Complete 25.2%, Processing 20.0%, Cancelled 14.8%, Returned 10.2%.
  Only Complete and Returned items reached the customer, so they form the denominator.
- Data quality: statuses and timestamps agree exactly; every return comes after a delivery.
- Returns are all-or-nothing per order: no order is partly returned.
- 26 categories, 2 departments, 10 centres, 2,756 brands (~23 delivered items per brand, so
  brands are only compared within one category, with a 50-item minimum).
- Channels: Search 70%, Organic 15%, Facebook 5.9%, Email 5.0%, Display 4.1% of users.
- Timing: delivery median 3.1 days (max 8); returns median 1.5 days after delivery (max 3).
  Some delivery times are negative (a generator quirk) and are treated as unknown.

**From `02_return_rate_overview`** (baseline 18,265 / 63,387 = 28.8%)
- Department: Men 28.8%, Women 28.8%.
- Distribution centre: 27.9% (Mobile AL) to 29.6% (Charleston SC); largest |z| 1.6.
- Traffic source: 28.0% (Organic, z = -1.7) to 29.0% (Search, Facebook).
- Category: 27.4% (Shorts) to 30.7% (Plus). Only Active crosses |z| > 2 (2.07); with 26
  categories ~1.3 would by chance. Bonferroni threshold |z| > ~3.1: none.
- Returned revenue: Outerwear & Coats 12.6% ($147 per return), Jeans 11.3% ($96),
  Sweaters 7.8%. Outerwear was chosen for the drill-down as the largest cost pool.

**From `03_root_cause_drilldown`** (target: Outerwear & Coats, 3,138 items, 29.25% vs 28.79%)
- Gap: 15 excess returns over 7.7 years (~2 a year).
- Brand: 15 brands with 50+ items; 20.0% to 33.6%; no |z| > 2.
- Price quartiles: Outerwear 28.6% to 29.9%; other categories 28.4% to 29.0%.
- Delivery time (other categories): 28.6% / 28.4% / 29.2% / 30.0% for under 2 / 2-4 / 4-6 /
  6+ days. Outerwear: 28.9% / 29.4% / 30.5% / 28.2% (only 266 items at 6+ days).
- Distribution centre: Outerwear 24.1% to 31.9%, but a few hundred items each; largest |z| ≈ 1.3.
  Average delivery 3.3 to 3.9 days at every centre.
- Not yet reviewed: channel, age band, discounting and quarterly trend (queries 3, 6, 7, 8).

## Appendix B: Definitions and method

- **Return rate** = returned items / delivered items (status Complete or Returned).
- **z-score** = (segment rate − overall rate) / √(overall rate × (1 − overall rate) / segment items).
  |z| > 2 ≈ 95% confidence for a single comparison.
- **Excess returns** = returns above what the comparison rate predicts for the segment's volume.
- Impact figures use 7.7 years of history; per-year values are totals ÷ 7.7.
- Full KPI definitions: `dashboard/metric_definitions.md`.
