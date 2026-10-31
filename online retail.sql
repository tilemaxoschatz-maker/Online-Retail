-- #####################################################################
-- ONLINE RETAIL II  |  COMPLETE WORKBOOK  (PostgreSQL: pgAdmin / Supabase)
-- #####################################################################
-- Source : UCI Machine Learning Repository, "Online Retail II" (CC BY 4.0)
--          https://archive.ics.uci.edu/dataset/502/online+retail+ii
-- Scope  : UK-based online gift-ware retailer, 2009-12-01 to 2011-12-09.
--          Many customers are wholesalers. Delivered as one Excel file
--          with two sheets (2009-2010 and 2010-2011).
--
-- Method : raw tables are never modified.
--            raw  ->  _copy tables (row_id + line_type)
--                 ->  retail_typed (typed, trimmed, duplicates flagged)
--                 ->  retail_clean (view used by every analysis)
--
--
-- HOW TO RUN  (pgAdmin: select text, then F5 - only the selection runs.
--              pgAdmin shows only the LAST result of whatever you run.)
--   PART 0  Select it and run ONCE on an empty database. It never drops
--           anything. Then import the two CSV files (Header = on) into
--           raw_retail_2009_2010 and raw_retail_2010_2011 (NOT the _copy
--           tables) and check the row counts.
--   PART 1  Select the whole part (Section 1 down to Section 4.5) and run
--           it in one go. The final result is a one-row summary.
--   PART 2  Run ONE query at a time: select it and press F5.
-- #####################################################################


-- #####################################################################
-- PART 0 - RAW TABLES (run once, then import the CSVs)
-- #####################################################################

-- Then (pgAdmin): right-click each table -> Import/Export Data
--   raw_retail_2009_2010  <- CSV of sheet "Year 2009-2010"
--   raw_retail_2010_2011  <- CSV of sheet "Year 2010-2011"
--   Format = csv, Header = on, Delimiter = ','
-- All columns are TEXT on purpose: nothing is rejected at load time and
-- every conversion happens (and is checked) in Part 1.

CREATE TABLE IF NOT EXISTS raw_retail_2009_2010 (
    "Invoice"     TEXT,
    "StockCode"   TEXT,
    "Description" TEXT,
    "Quantity"    TEXT,
    "InvoiceDate" TEXT,
    "Price"       TEXT,
    "Customer ID" TEXT,
    "Country"     TEXT
);
CREATE TABLE IF NOT EXISTS raw_retail_2010_2011 (LIKE raw_retail_2009_2010);

-- Check after both imports (expected 525,461 / 541,910 / 1,067,371):
-- SELECT (SELECT COUNT(*) FROM raw_retail_2009_2010) AS rows_2009_2010,
--        (SELECT COUNT(*) FROM raw_retail_2010_2011) AS rows_2010_2011;


-- #####################################################################
-- PART 1 - SETUP & CLEANING (run as one selection)
-- #####################################################################

-- =====================================================================
-- SECTION 1 · WORKING COPIES  (row_id + line_type)
-- =====================================================================
-- line_type classifies every row so that revenue is only ever computed
-- from the right rows:
--   sale          quantity > 0, invoice not a cancellation, price > 0
--   cancellation  invoice starts with 'C' and quantity < 0
--   adjustment    quantity < 0, no 'C' prefix (stock write-offs: price 0,
--                 no customer, free-text notes such as 'damaged', 'missing')
--   zero_price    quantity > 0 but price = 0 (stock corrections, not sales)
--   manual_entry  'C' invoice with positive quantity (manual ledger entry,
--                 1 row, value 374)
--   accounting_adjustment  quantity > 0 but price < 0: bad-debt write-offs
--                 (stock code B, no customer, 5 rows). Not sales.
--   unknown       quantity is not a whole number (none found in this data)

-- ---------- Copy 1: 2009-2010 ----------
DROP TABLE IF EXISTS raw_retail_2009_2010_copy;
CREATE TABLE raw_retail_2009_2010_copy AS
SELECT "Invoice"     AS invoice,
       "StockCode"   AS stock_code,
       "Description" AS description,
       "Quantity"    AS quantity,
       "InvoiceDate" AS invoice_date,
       "Price"       AS price,
       "Customer ID" AS customer_id,
       "Country"     AS country
FROM raw_retail_2009_2010;

ALTER TABLE raw_retail_2009_2010_copy ADD COLUMN row_id BIGINT GENERATED ALWAYS AS IDENTITY;
ALTER TABLE raw_retail_2009_2010_copy ADD COLUMN line_type TEXT;

UPDATE raw_retail_2009_2010_copy
SET line_type = CASE
    WHEN quantity !~ '^-?[0-9]+$' THEN 'unknown'
    WHEN invoice LIKE 'C%'        THEN 'cancellation'
    WHEN quantity::int < 0        THEN 'adjustment'
    WHEN quantity::int > 0        THEN 'sale'
    ELSE 'unknown'
END
WHERE TRUE;

-- 'C' invoice with positive quantity is not a real cancellation
UPDATE raw_retail_2009_2010_copy
SET line_type = 'manual_entry'
WHERE invoice LIKE 'C%'
  AND quantity ~ '^-?[0-9]+$' AND quantity::int > 0;

-- Positive quantity at price 0 is not revenue-generating
UPDATE raw_retail_2009_2010_copy
SET line_type = 'zero_price'
WHERE line_type = 'sale'
  AND price ~ '^-?[0-9]+(\.[0-9]+)?$' AND price::numeric = 0;

-- Negative price = accounting entry (e.g. 'Adjust bad debt', stock code B),
-- not a sale
UPDATE raw_retail_2009_2010_copy
SET line_type = 'accounting_adjustment'
WHERE line_type = 'sale'
  AND price ~ '^-[0-9]+(\.[0-9]+)?$';

-- ---------- Copy 2: 2010-2011 ----------
DROP TABLE IF EXISTS raw_retail_2010_2011_copy;
CREATE TABLE raw_retail_2010_2011_copy AS
SELECT "Invoice"     AS invoice,
       "StockCode"   AS stock_code,
       "Description" AS description,
       "Quantity"    AS quantity,
       "InvoiceDate" AS invoice_date,
       "Price"       AS price,
       "Customer ID" AS customer_id,
       "Country"     AS country
FROM raw_retail_2010_2011;

ALTER TABLE raw_retail_2010_2011_copy ADD COLUMN row_id BIGINT GENERATED ALWAYS AS IDENTITY;
ALTER TABLE raw_retail_2010_2011_copy ADD COLUMN line_type TEXT;

UPDATE raw_retail_2010_2011_copy
SET line_type = CASE
    WHEN quantity !~ '^-?[0-9]+$' THEN 'unknown'
    WHEN invoice LIKE 'C%'        THEN 'cancellation'
    WHEN quantity::int < 0        THEN 'adjustment'
    WHEN quantity::int > 0        THEN 'sale'
    ELSE 'unknown'
END
WHERE TRUE;

UPDATE raw_retail_2010_2011_copy
SET line_type = 'manual_entry'
WHERE invoice LIKE 'C%'
  AND quantity ~ '^-?[0-9]+$' AND quantity::int > 0;

UPDATE raw_retail_2010_2011_copy
SET line_type = 'zero_price'
WHERE line_type = 'sale'
  AND price ~ '^-?[0-9]+(\.[0-9]+)?$' AND price::numeric = 0;

-- Negative price = accounting entry (e.g. 'Adjust bad debt', stock code B),
-- not a sale
UPDATE raw_retail_2010_2011_copy
SET line_type = 'accounting_adjustment'
WHERE line_type = 'sale'
  AND price ~ '^-[0-9]+(\.[0-9]+)?$';


-- =====================================================================
-- SECTION 2 · TYPED TABLE  (types, trimming, duplicate flag)
-- =====================================================================
-- * Both sheets are stacked; source_sheet records where each row came from.
-- * Text is trimmed and empty strings become NULL.
-- * Numbers and timestamps are converted only when the text matches the
--   expected pattern, otherwise NULL (checked in Section 4: no failures).
-- * Dates arrive as M/D/YY H:mm (e.g. 12/1/09 7:45 = 1 Dec 2009).
-- * is_duplicate: a row is a duplicate when every business column matches
--   an earlier row. The two sheets overlap in early December 2010, so the
--   comparison runs across both sheets together. The first occurrence is
--   kept (ordered by sheet, then row_id). Rows are flagged, not deleted.
-- * is_product_code: stock codes that start with 5 digits are products;
--   others (e.g. M, POST, BANK CHARGES) are fees or manual entries.
-- * line_total = quantity * price (negative for cancellations).

DROP VIEW  IF EXISTS public.retail_clean;
DROP TABLE IF EXISTS public.retail_typed;

CREATE TABLE public.retail_typed AS
WITH unioned AS (
    SELECT '2009_2010' AS source_sheet, row_id, invoice, stock_code, description,
           quantity, invoice_date, price, customer_id, country, line_type
    FROM raw_retail_2009_2010_copy
    UNION ALL
    SELECT '2010_2011', row_id, invoice, stock_code, description,
           quantity, invoice_date, price, customer_id, country, line_type
    FROM raw_retail_2010_2011_copy
),
cleaned AS (
    SELECT source_sheet, row_id,
           NULLIF(TRIM(invoice), '')     AS invoice,
           NULLIF(TRIM(stock_code), '')  AS stock_code,
           NULLIF(TRIM(description), '') AS description,
           CASE WHEN quantity ~ '^-?[0-9]+$' THEN quantity::int END AS quantity,
           CASE WHEN invoice_date ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2} [0-9]{1,2}:[0-9]{2}$'
                THEN TO_TIMESTAMP(invoice_date, 'MM/DD/YY HH24:MI')::timestamp END AS invoice_ts,
           CASE WHEN price ~ '^-?[0-9]+(\.[0-9]+)?$' THEN price::numeric END AS price,
           CASE WHEN TRIM(customer_id) ~ '^[0-9]+$' THEN TRIM(customer_id)::int END AS customer_id,
           NULLIF(TRIM(country), '')     AS country,
           line_type
    FROM unioned
)
SELECT c.*,
       (c.stock_code ~ '^[0-9]{5}')   AS is_product_code,
       ROUND(c.quantity * c.price, 2) AS line_total,
       ROW_NUMBER() OVER (
           PARTITION BY invoice, stock_code, description, quantity,
                        invoice_ts, price, customer_id, country
           ORDER BY source_sheet, row_id
       ) > 1                           AS is_duplicate
FROM cleaned c;


-- =====================================================================
-- SECTION 3 · CLEAN VIEW  (the only object analyses should read from)
-- =====================================================================
CREATE OR REPLACE VIEW public.retail_clean AS
SELECT *
FROM public.retail_typed
WHERE NOT is_duplicate;


-- =====================================================================
-- SECTION 4 · VALIDATION  (run after the build)
-- =====================================================================
-- 4.1  Nothing lost, nothing failed to convert.
--      Expected on the UCI file: total = expected_total = 1,067,371, bad_* = 0
SELECT COUNT(*) AS total,
       COUNT(*) FILTER (WHERE invoice_ts IS NULL) AS bad_ts,
       COUNT(*) FILTER (WHERE quantity   IS NULL) AS bad_quantity,
       COUNT(*) FILTER (WHERE price      IS NULL) AS bad_price,
       (SELECT COUNT(*) FROM raw_retail_2009_2010)
     + (SELECT COUNT(*) FROM raw_retail_2010_2011) AS expected_total
FROM public.retail_typed;

-- 4.2  Row classes and duplicates per sheet.
--      Expected for sheet 2009_2010: duplicates 6,865,
--      sale 511,568 / cancellation 10,205 / adjustment 2,121 /
--      zero_price 1,566 / manual_entry 1 (before removing duplicates).
--      Sheet 2010_2011 flags 27,470 rows as duplicates: this includes
--      rows repeated inside the sheet and rows already present in sheet 1.
SELECT source_sheet, line_type, is_duplicate, COUNT(*) AS n
FROM public.retail_typed
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- 4.3  Clean row count.  Expected: 1,033,036
--      (1,067,371 - 6,865 - 27,470 = 1,033,036)
SELECT COUNT(*) AS clean_rows FROM public.retail_clean;

-- 4.4  Grain check: one row = one product line on one invoice.
--      Expected on clean data: ~1.03M rows, ~53.6K invoices, ~5.9K customers.
--      (Customers exclude guest rows, where customer_id is NULL, ~20% of rows.)
SELECT COUNT(*)                    AS line_rows,
       COUNT(DISTINCT invoice)     AS invoices,
       COUNT(DISTINCT customer_id) AS customers
FROM public.retail_clean;


-- 4.5  ONE-ROW SUMMARY (pgAdmin shows only the last result of a script,
--      so run Part 1 as a whole and read everything here).
--      Expected: raw_rows 1,067,371 | typed_rows 1,033,036+34,335 = 1,067,371
--                clean_rows 1,033,036 | bad_* 0 | ~53.6K invoices | ~5.9K customers
SELECT (SELECT COUNT(*) FROM raw_retail_2009_2010) + (SELECT COUNT(*) FROM raw_retail_2010_2011) AS raw_rows,
       (SELECT COUNT(*) FROM public.retail_typed)  AS typed_rows,
       (SELECT COUNT(*) FROM public.retail_clean)  AS clean_rows,
       (SELECT COUNT(*) FROM public.retail_typed WHERE invoice_ts IS NULL OR quantity IS NULL OR price IS NULL) AS bad_rows,
       (SELECT COUNT(DISTINCT invoice) FROM public.retail_clean)     AS invoices,
       (SELECT COUNT(DISTINCT customer_id) FROM public.retail_clean) AS customers;


-- =====================================================================
-- SECTION 5 · HOUSEKEEPING  (free-tier storage)
-- =====================================================================
-- The two _copy tables are only an intermediate step: retail_typed was
-- built from them with CREATE TABLE AS and does not depend on them.
-- On the free Supabase plan (~500 MB database limit) they can be dropped
-- once Section 4 passes; Sections 1-2 rebuild them from the raw tables.
-- (The two copies took ~260 MB. The database was 286 MB after the
--  copies and an old backup table were dropped.)
--
-- DROP TABLE IF EXISTS raw_retail_2009_2010_copy;
-- DROP TABLE IF EXISTS raw_retail_2010_2011_copy;
--
-- SELECT relname AS table_name,
--        pg_size_pretty(pg_total_relation_size(relid)) AS total_size
-- FROM pg_catalog.pg_statio_user_tables
-- ORDER BY pg_total_relation_size(relid) DESC;


-- =====================================================================
-- DATA-QUALITY FINDINGS  (for the README)
-- =====================================================================
-- 1. Duplicates: 34,335 rows (3.2%) were flagged and excluded from
--    retail_clean: 6,865 in the first sheet and 27,470 in the second,
--    the latter including rows already present in the first sheet
--    (the two sheets overlap in early December 2010). The split between
--    overlap and within-sheet duplicates has not been measured.
-- 2. Row classes: of 1,033,036 clean rows, 1,007,918 are sales, 19,103
--    cancellations, 3,393 stock adjustments, 2,621 zero-price rows and
--    1 manual entry. Only sales and cancellations carry value.
-- 3. Guest orders: ~20% of rows have no customer_id. They are kept in
--    revenue analyses and excluded from customer-level analyses.
-- 4. Product names: description is not a reliable key. 622 of 4,877
--    product codes with sales have more than one description (names
--    change over time) and non-sale rows carry free-text stock notes.
--    stock_code is the product key; display names will come from the
--    most frequent description per code among sales.
-- 5. Orders placed and cancelled within minutes inflate gross revenue:
--    customer 12346 (74,215 units of 23166, 77,184, 2011-01-18) and
--    customer 16446 (80,995 units of 23843, 168,470, 2011-12-09).
--    Together 245,653, 1.2% of gross sales. Analyses therefore use net
--    revenue (see Part 2).
-- 7. Accounting entries: 5 rows with positive quantity and a NEGATIVE
--    price ('Adjust bad debt', stock code B, no customer, 158,676 in
--    total) were first classified as sales and pushed gross revenue down.
--    Found when the order-value deciles (BQ10) showed negative orders.
--    They are now line_type = 'accounting_adjustment' and excluded from
--    sales and from net revenue.
-- 6. Country values: 'Unspecified' and 'European Community' are not real
--    countries and are left as recorded.


-- #####################################################################
-- PART 2 - BUSINESS QUESTIONS (run one query at a time)
-- #####################################################################

-- REVENUE DEFINITIONS
--   Gross revenue = SUM(line_total) over line_type = 'sale'.
--   Net revenue   = SUM(line_total) over line_type IN ('sale','cancellation').
--                   Cancellation rows carry negative amounts, so a plain SUM
--                   subtracts them.
--   Net revenue is the standard for revenue questions, because some very
--   large orders were placed and cancelled within minutes (see BQ06b);
--   counting only sales would credit the business with revenue it never
--   kept. BQ06, BQ07, BQ09, BQ09b and BQ10 are on a gross basis on
--   purpose: they describe cancellations or order behaviour themselves.
--   Whole dataset: gross 20,476,260; cancellations -1,462,424 (7.1% of
--   gross); net 19,013,836. (Before the accounting_adjustment rule the
--   figures were 20,317,584 / 18,855,160, see Part 1 finding 7.)
--   Order counts use COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale'),
--   so cancellation invoices (prefix 'C') are not counted as orders.
--
-- OTHER CONVENTIONS
--   * Products are identified by stock_code (descriptions change over time).
--     Rows whose stock_code is not a product (fees, manual entries) are
--     excluded with is_product_code.
--   * Customer-level questions exclude guest rows (customer_id IS NULL).
--   * The dataset has no product cost, so profit cannot be computed.
--     No claim is made about margin.
--   * The Supabase SQL Editor shows at most 100 rows: use COUNT(*) for totals.
--
-- STATUS
--   Net revenue basis: BQ01, BQ02, BQ03, BQ03b, BQ04, BQ05, BQ08.
--   Gross (sales only), by design: BQ06, BQ07, BQ09, BQ09b, BQ10.
--   All results quoted below were produced after the accounting_adjustment
--   rule (Part 1).
-- =====================================================================


-- ---------------------------------------------------------------------
-- BQ01 · Which products generate the most net revenue, and how many
--        units do they sell?
-- Decision: which products to keep permanently in stock and promote.
-- Finding: product 22423 leads with 314,045 net revenue, followed by
--          85123A (248,338) and 85099B (178,401). 22423 earns ~12.5 per
--          unit against ~2.7 for 85123A, so the top revenue product is
--          driven by price, not by volume.
-- Effect of using net instead of gross revenue (gross top 20 vs net):
--          products 23843 and 23166 drop out of the top 20 and 22502 and
--          21621 enter. 23843's sales were a single 80,995-unit order
--          (168,470) that was cancelled; 94.5% of 23166's gross revenue
--          was one 74,215-unit order (77,184), also cancelled.
--          22423 falls from 330,590 to 314,045 (-5.0%), 85123A from
--          257,725 to 248,338 and 85099B from 180,569 to 178,401.
-- ---------------------------------------------------------------------
SELECT stock_code,
       SUM(quantity)   AS net_units_sold,
       SUM(line_total) AS net_revenue
FROM public.retail_clean
WHERE line_type IN ('sale', 'cancellation')
  AND is_product_code
GROUP BY stock_code
ORDER BY net_revenue DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- BQ02 · Which products sell very high volumes but earn very little
--        revenue per unit?
-- Decision: whether to review pricing, bundle, or keep promoting these
--           products, before judging them on revenue alone.
-- Definition: "high volume" = top 10% of products by net units sold.
--             "low revenue per unit" = bottom 25% of products by net
--             revenue per unit (net revenue / net units, a ratio of
--             totals, not an average of line prices). Thresholds come
--             from the data. Products with zero or negative net units
--             are excluded (division by zero / meaningless ratio).
-- Finding: 208 of 4,858 products meet both conditions. At the top are
--          84077 (104,435 net units, 24,084 revenue, 0.23 per unit),
--          21212 (93,774; 51,275; 0.55), 22197 (87,695; 78,904; 0.90)
--          and 17003 (69,629; 14,551; 0.21). By comparison 85123A, a top
--          revenue product, earns ~2.7 per unit. The same products lead
--          on a gross and a net basis: the cancellation effect on them
--          is small.
-- Caveat: without product cost this says nothing about margin. Whether
--         these items are add-ons to larger baskets needs a basket
--         analysis.
-- ---------------------------------------------------------------------
WITH product AS (
    SELECT stock_code,
           SUM(quantity)   AS net_quantity,
           SUM(line_total) AS net_revenue,
           ROUND(SUM(line_total) / SUM(quantity), 2) AS revenue_per_unit
    FROM public.retail_clean
    WHERE line_type IN ('sale', 'cancellation')
      AND is_product_code
    GROUP BY stock_code
    HAVING SUM(quantity) > 0
),
cuts AS (
    SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY net_quantity)     AS qty_top10pct,
           PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue_per_unit) AS price_bottom25pct
    FROM product
)
SELECT p.*
FROM product p
CROSS JOIN cuts c
WHERE p.net_quantity     >= c.qty_top10pct
  AND p.revenue_per_unit <= c.price_bottom25pct
ORDER BY p.net_quantity DESC;

-- BQ02 · count of matching products (the editor only shows 100 rows).
--        Result: products_matching = 208, products_total = 4,858.
-- WITH product AS ( ...same as above... ),
-- cuts AS ( ...same as above... )
-- SELECT COUNT(*) AS products_matching,
--        (SELECT COUNT(*) FROM product) AS products_total
-- FROM product p CROSS JOIN cuts c
-- WHERE p.net_quantity >= c.qty_top10pct
--   AND p.revenue_per_unit <= c.price_bottom25pct;


-- ---------------------------------------------------------------------
-- BQ03 · How do monthly net revenue and order volume change through the
--        year, and in which months do they peak?
-- Decision: when to build stock and plan promotions ahead of peak demand.
-- Basis: net revenue (sales + cancellations), shown next to gross.
--        Cancellations are booked in the month they occur, not in the
--        month of the original sale.
-- Scope: December 2011 is excluded because the data ends on 9 December
--        2011; a partial month is not comparable with full months.
-- Finding: net revenue peaks in September-November in both years
--          (Nov 2010: 1,416,697; Nov 2011: 1,456,146) and falls in
--          December (Dec 2009: 796,649; Dec 2010: 746,724). Net revenue
--          is 3-19% below gross depending on the month. The largest gap
--          is January 2011 (558,449 net against 689,812 gross), which
--          contains the 77,184 order that customer 12346 placed and
--          cancelled on the same day (BQ06b). On a net basis January
--          2011 is 10.3% below January 2010 (622,480), while gross
--          showed a rise. Working hypothesis: the customer base is
--          largely wholesale, buying ahead of the festive season. This
--          is a hypothesis; the data has no customer-type field.
-- ---------------------------------------------------------------------
SELECT DATE_TRUNC('month', invoice_ts)::date                            AS month,
       ROUND(SUM(line_total))                                           AS net_revenue,
       ROUND(SUM(line_total) FILTER (WHERE line_type = 'sale'))         AS gross_revenue,
       COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale')        AS orders
FROM public.retail_clean
WHERE line_type IN ('sale', 'cancellation')
  AND invoice_ts < DATE '2011-12-01'
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- BQ03b · Does the seasonal pattern repeat from one year to the next?
-- Decision: whether stock and promotion plans can be built on the same
--           yearly calendar, or need to be reassessed every year.
-- Basis: net revenue (sales + cancellations). Cancellations are booked
--        in the month they occur, not in the month of the original sale.
-- Scope: January-November, 2010 vs 2011. December is excluded from both
--        years (December 2011 is incomplete; December 2010 would have no
--        2011 counterpart).
-- Finding: the three highest months are September, October and November
--          in both years, in the same order (Nov > Oct > Sep).
--          September-November delivers 39.5% of January-November net
--          revenue in 2010 and 41.3% in 2011. Total January-November net
--          revenue grew 1.2% (8.47M -> 8.57M).
--          The year is not evenly better: January-April 2011 was below
--          2010 in every month (-10.3%, -6.4%, -10.6%, -23.2%; -12.8% in
--          total), then May-November was 7.2% above 2010. October is flat
--          (-1.0%), September is strongest (+19.6%). So the reliable
--          signal is the autumn peak, not the month-to-month detail.
--          The lowest month is February in 2010 (530,892) but April in
--          2011 (492,368); on a gross basis February was lowest in both
--          years, so this depends on how cancellations are treated.
-- Caveat: only two years of data; two repeats suggest a pattern but do
--         not prove it.
-- ---------------------------------------------------------------------
SELECT EXTRACT(MONTH FROM invoice_ts)::int AS month_no,
       ROUND(SUM(line_total) FILTER (WHERE EXTRACT(YEAR FROM invoice_ts) = 2010)) AS net_2010,
       ROUND(SUM(line_total) FILTER (WHERE EXTRACT(YEAR FROM invoice_ts) = 2011)) AS net_2011,
       ROUND(100.0 * (SUM(line_total) FILTER (WHERE EXTRACT(YEAR FROM invoice_ts) = 2011)
                    - SUM(line_total) FILTER (WHERE EXTRACT(YEAR FROM invoice_ts) = 2010))
             / NULLIF(SUM(line_total) FILTER (WHERE EXTRACT(YEAR FROM invoice_ts) = 2010), 0), 1) AS pct_change
FROM public.retail_clean
WHERE line_type IN ('sale', 'cancellation')
  AND invoice_ts >= DATE '2010-01-01'
  AND invoice_ts <  DATE '2011-12-01'
  AND EXTRACT(MONTH FROM invoice_ts) <= 11
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- BQ04 · What share of net revenue does each country generate, and how
--        large is the average order in each?
-- Decision: where to build key-account relationships, and how to reduce
--           dependence on a single market (the UK).
-- Basis: net revenue (sales + cancellations).
-- Metric:  net_revenue_per_order = net revenue / number of distinct sale
--          invoices (a ratio of totals, not an average of line values).
--          A country with only cancellations has no orders and no ratio.
-- Finding: the UK generates 84.9% of net revenue (16.14M over 36,535
--          orders, ~442 per order). The next largest markets are
--          Ireland (3.2%, ~974 per order), the Netherlands (2.9%) and
--          Germany (2.2%). Order size differs widely outside the UK: the
--          Netherlands (~2,405 per order), Australia (~1,752) and
--          Denmark (~1,499) place few but very large orders, about 3-5x
--          the UK average, while Germany (522), France (517) and Belgium
--          (424) look like the UK. Export markets with large orders look
--          like key-account relationships rather than mass-market sales.
--          This is a hypothesis: the data has no customer-type field.
--          Cancellations differ by market. Comparing net with gross
--          revenue, the Netherlands loses about 1%, Germany about 3% and
--          the UK about 7%, while Norway (-37%), Hong Kong (-42%) and
--          Singapore (-48%) lose much more. The last three have few
--          orders (45, 15 and 11), so their figures are not reliable.
-- Caveats: averages for countries with few orders are unreliable
--          (e.g. Singapore: 11 orders, Hong Kong: 15, Thailand: 2).
--          'Unspecified' and 'European Community' are not real countries
--          and are left as recorded. The gross figures used for the
--          comparison above come from the earlier gross version of this
--          query.
-- ---------------------------------------------------------------------
SELECT country,
       ROUND(SUM(line_total))                                           AS net_revenue,
       COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale')        AS orders,
       ROUND(SUM(line_total)
             / NULLIF(COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale'), 0)) AS net_revenue_per_order,
       ROUND(100.0 * SUM(line_total) / SUM(SUM(line_total)) OVER (), 1) AS pct_of_net_revenue
FROM public.retail_clean
WHERE line_type IN ('sale', 'cancellation')
GROUP BY country
ORDER BY net_revenue DESC;


-- ---------------------------------------------------------------------
-- BQ05 · Which customers generate the most net revenue, and how
--        concentrated is revenue among a small group of customers?
-- Decision: which accounts need dedicated attention, and how exposed the
--           business is to losing a few large customers.
-- Scope: customers with a known customer_id only (guest rows, ~20% of
--        rows, cannot be attributed to a customer).
-- Finding: the top 20 customers generate 3.52M net revenue, 18.5% of
--          total net revenue (19.01M, guest sales included in the
--          total). Customers 16446 and 12346 drop out of the ranking on
--          a net basis (see BQ06b). Order frequency and size differ
--          widely: customer 14911 placed 398 orders (~668 net each),
--          customer 17450 placed 51 orders (~4,537 each).
--          Cancellations hit some top customers much harder than others
--          (share of gross revenue cancelled): 16029: 23.8%, 12931:
--          22.8%, 17949: 16.8%, 14911: 8.8%, versus 18102: 1.8% and
--          14646: 1.0%.
-- ---------------------------------------------------------------------
SELECT customer_id,
       COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale')       AS orders,
       ROUND(SUM(line_total))                                          AS net_revenue,
       ROUND(SUM(line_total)
             / NULLIF(COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale'), 0)) AS net_revenue_per_order
FROM public.retail_clean
WHERE line_type IN ('sale', 'cancellation')
  AND customer_id IS NOT NULL
GROUP BY customer_id
ORDER BY net_revenue DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- BQ06 · How large are cancellations relative to sales?
-- Decision: how much revenue is lost to cancellations, and whether
--           large orders need a different process (deposit, approval).
-- Finding: cancellations are 19,103 rows (1.9% of rows) but -1.46M,
--          7.1% of gross sales value (20.5M, after reclassifying the
--          accounting entries). The average cancellation
--          row is ~77 against ~20 for a sale row, so large orders are
--          cancelled disproportionately. Stock adjustments (3,393 rows)
--          and zero-price rows (2,621 rows) carry no value. Five
--          accounting entries ('Adjust bad debt', -158,676) are kept
--          separate as accounting_adjustment.
-- Caveat: cancellation invoices carry no link to the original invoice,
--         so matching a cancellation to its sale needs customer,
--         product, quantity and time (see BQ06b).
-- ---------------------------------------------------------------------
SELECT line_type,
       COUNT(*)               AS line_rows,
       ROUND(SUM(line_total)) AS value
FROM public.retail_clean
GROUP BY line_type
ORDER BY value DESC;

-- BQ06b · Verification: very large lines for the two customers with
--         unusual order counts in the gross top 20.
-- Finding: both placed one very large order and cancelled the identical
--          quantity within minutes:
--            12346: 74,215 units of 23166, 2011-01-18 10:01 sold, 10:17 cancelled (77,183.60)
--            16446: 80,995 units of 23843, 2011-12-09 09:15 sold, 09:27 cancelled (168,469.60)
--          Together 245,653 of gross sales (1.2%) were cancelled
--          almost immediately. On a gross basis these two orders put
--          products 23166 and 23843 in the top 20 by revenue.
SELECT customer_id, invoice, line_type, stock_code, quantity, price,
       line_total, invoice_ts
FROM public.retail_clean
WHERE customer_id IN (16446, 12346)
  AND ABS(line_total) > 10000
ORDER BY customer_id, invoice_ts;

-- ---------------------------------------------------------------------
-- BQ07 · Which customers cancel the largest share of their sales, and
--        does the answer change if we rank by cancelled value instead?
-- Decision: which accounts need a different order process (deposit,
--           approval for large orders) and which can be left alone.
-- Basis: gross sales and cancelled value per customer.
--        pct_cancelled = cancelled value / gross sales (a ratio of totals).
-- Scope: customers with a known customer_id and at least 10 sales
--        orders. The threshold is a judgement call: below it, one or two
--        orders produce extreme percentages that say little about
--        behaviour.
-- Finding: ranked by percentage, the top of the list is mostly small
--          accounts: 15369 (72.6% of 6,251), 12755 (50.1% of 5,236) and
--          17867 (45.9% of 1,582). The money at stake there is small
--          (726-4,538 cancelled each). Ranked by cancelled value, the
--          largest accounts stand out: 16029 (28,058 cancelled, 23.8%
--          of 117,764), 12931 (21,048, 22.8% of 92,347) and 12744
--          (12,159, 48.0% of 25,317). A process change should therefore
--          start with the few large accounts, not the highest percentages.
-- Exception: customer 12346 shows 100.1% because most of its sales were
--          the single order placed and cancelled within minutes (BQ06b).
--          Its cancellations (77,608) exceed its sales (77,556), possibly
--          because some cancellations relate to purchases made before the
--          data starts. This is a hypothesis and has not been checked.
--          It is a one-off event, not typical customer behaviour.
-- Caveat: cancellation rows carry no link to the original invoice, so
--         the share is measured on value, not on matched orders.
--         The ranking by cancelled value was read from the same table,
--         not from a separate query.
-- ---------------------------------------------------------------------
SELECT customer_id,
       COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale')           AS orders,
       ROUND(SUM(line_total)  FILTER (WHERE line_type = 'sale'))           AS gross_sales,
       ROUND(SUM(-line_total) FILTER (WHERE line_type = 'cancellation'))   AS cancelled_value,
       ROUND(100.0 * SUM(-line_total) FILTER (WHERE line_type = 'cancellation')
             / NULLIF(SUM(line_total) FILTER (WHERE line_type = 'sale'), 0), 1) AS pct_cancelled
FROM public.retail_clean
WHERE line_type IN ('sale', 'cancellation')
  AND customer_id IS NOT NULL
GROUP BY customer_id
HAVING COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale') >= 10
ORDER BY pct_cancelled DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- BQ08 · How many customers buy only once and how many come back, and
--        how much net revenue does each group generate?
-- Decision: whether to invest in winning new customers or in keeping the
--           ones already acquired (reorder reminders, account management).
-- Basis: net revenue per customer (sales + cancellations).
-- Scope: customers with a known customer_id and at least one sale order
--        (guest rows cannot be tied to a customer; customers with only
--        cancellations are excluded because they have no purchase in the
--        data).
-- Grain: one row per customer in the CTE, orders counted as distinct
--        sale invoices (a customer has many orders, an order has many
--        lines). Customers are grouped into bands by number of orders.
-- Finding: of 5,878 customers with at least one purchase, 27.6% (1,623)
--          bought only once, but they generate just 3.2% of net revenue
--          (517K). At the other end, 16.6% of customers (974) placed 10
--          or more orders and generate 68.3% of net revenue (11.17M).
--          The middle bands add up to 55.8% of customers and 28.5% of
--          revenue. Revenue therefore depends on a loyal core of
--          repeat buyers, which is consistent with the concentration seen
--          in BQ05. For the decision: retention and account management
--          for the 10+ order group matter far more than converting the
--          one-time buyers.
--          Working hypothesis: the 10+ group are mostly trade customers
--          reordering regularly; the data has no customer-type field.
-- Caveat: the data covers about two years. A customer with one order may
--         have returned before 2009-12 or after 2011-12; "bought once"
--         means once within this window.
-- ---------------------------------------------------------------------
WITH customer AS (
    SELECT customer_id,
           COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale') AS orders,
           SUM(line_total)                                           AS net_revenue
    FROM public.retail_clean
    WHERE line_type IN ('sale', 'cancellation')
      AND customer_id IS NOT NULL
    GROUP BY customer_id
    HAVING COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale') > 0
)
SELECT CASE WHEN orders = 1              THEN '1 order'
            WHEN orders BETWEEN 2 AND 4  THEN '2-4 orders'
            WHEN orders BETWEEN 5 AND 9  THEN '5-9 orders'
            ELSE '10+ orders' END                                   AS order_band,
       COUNT(*)                                                     AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_customers,
       ROUND(SUM(net_revenue))                                      AS net_revenue,
       ROUND(100.0 * SUM(net_revenue) / SUM(SUM(net_revenue)) OVER (), 1) AS pct_revenue
FROM customer
GROUP BY 1
ORDER BY MIN(orders);


-- ---------------------------------------------------------------------
-- BQ09 · On which days of the week do orders arrive, and how large are
--        they?
-- Decision: how to schedule staff and dispatch across the week.
-- Basis: gross sales (sales only). Orders = COUNT(DISTINCT invoice), so
--        invoice lines are not counted as orders.
-- Finding: Thursday has the most orders (8,288, 20.7% of all orders),
--          followed by Tuesday (18.2%) and Wednesday (17.9%). Thursday
--          and Tuesday bring similar revenue (20.5% and 19.9%). Saturday
--          is almost empty: 30 orders (0.1%) in two years, which
--          suggests the company does not operate on Saturdays. This is a
--          hypothesis; the data has no opening hours. Sunday has 12.1%
--          of orders but only 8.8% of revenue, because the average order
--          is smaller (about 372 against about 486-564 on weekdays).
-- Assessment: the weekly pattern is moderate. Weekdays are broadly
--          similar (15-21% of orders each), so the useful signals are
--          the Thursday peak, the closed Saturday and the smaller
--          Sunday orders.
-- Caveat: invoice_ts is the time recorded on the invoice, not the
--         dispatch or delivery time.
-- ---------------------------------------------------------------------
SELECT EXTRACT(ISODOW FROM invoice_ts)::int AS day_no,
       TRIM(TO_CHAR(invoice_ts, 'Day'))     AS day_name,
       COUNT(DISTINCT invoice)              AS orders,
       ROUND(SUM(line_total))               AS revenue
FROM public.retail_clean
WHERE line_type = 'sale'
GROUP BY 1, 2
ORDER BY day_no;


-- ---------------------------------------------------------------------
-- BQ09b · At which hours of the day do orders arrive, and how large are
--         they?
-- Decision: when to have order picking and customer service fully
--           staffed during the working day.
-- Basis: gross sales (sales only), orders = COUNT(DISTINCT invoice).
-- Finding: activity is concentrated between 10:00 and 15:59, which
--          carries about 78% of all orders (31,272 of 40,078). The peak
--          hour is 12:00 with 6,427 orders (16.0%), followed by 13:00
--          (14.2%) and 14:00 (12.7%). Orders start around 08:00 and fade
--          after 17:00; 18:00-20:00 together hold about 2.1% of orders.
--          Order value moves the other way: revenue per order is lowest
--          around midday (about 444-458 at 12:00-14:00) and highest in
--          the morning (643 at 09:00). Working hypothesis: smaller or
--          more frequent orders arrive at midday, larger orders earlier
--          and later in the day. The data does not identify customer
--          type, so this is untested.
-- Caveats: the earliest and latest hours have very few orders (06:00: 1,
--          07:00: 77, 20:00: 53), so their revenue per order (4, 984,
--          734) is not reliable. An invoice whose lines straddle an hour
--          boundary is counted in both hours, which is why the total
--          here (40,078) is one higher than in BQ09 (40,077). The hour
--          is the time stored on the invoice, in the system's time zone.
-- ---------------------------------------------------------------------
SELECT EXTRACT(HOUR FROM invoice_ts)::int                              AS hour_of_day,
       COUNT(DISTINCT invoice)                                         AS orders,
       ROUND(100.0 * COUNT(DISTINCT invoice)
             / SUM(COUNT(DISTINCT invoice)) OVER (), 1)                AS pct_orders,
       ROUND(SUM(line_total))                                          AS revenue,
       ROUND(SUM(line_total) / COUNT(DISTINCT invoice))                AS revenue_per_order
FROM public.retail_clean
WHERE line_type = 'sale'
GROUP BY 1
ORDER BY hour_of_day;


-- ---------------------------------------------------------------------
-- BQ10 · How is revenue distributed across small and large orders?
-- Decision: whether to focus on the few very large orders or to try to
--           lift the size of mid-sized ones (for example, a volume
--           discount test).
-- Method: sale invoices are ranked by order value and split into 10 equal
--         groups (NTILE). Group 1 holds the smallest 10% of orders,
--         group 10 the largest. Each row shows the group's value range
--         and its share of total revenue.
-- Basis: gross sales (sales only), one row per invoice.
-- Checks: 40,077 orders and 20,476,260 revenue, matching the sale totals.
-- Finding: revenue is highly concentrated in large orders. The largest
--          10% of orders (above 930) generate 47.8% of revenue
--          (9.79M), and the largest 30% (groups 8-10) generate 71.6%.
--          The smaller half of orders (up to about 302) generates only
--          14.6%. The average order (about 511) is well above the middle
--          of the distribution (about 302), because a small number of
--          very large orders pull the average up.
-- Implication: order-handling effort (stock availability, credit
--          checks, dispatch) matters most for the top group. A discount
--          to lift small orders would affect a group that holds under
--          15% of revenue, so it is a lower-priority lever. Without
--          product cost, whether any discount is profitable cannot be
--          judged from this data; it would need to be tested.
-- Caveat: the largest order in group 10 (168,470) is the order that
--         customer 16446 cancelled within minutes (BQ06b). It is 1.7% of
--         group 10 revenue, so the conclusion does not change.
--         Cancellations are separate invoices and are not netted here.
-- ---------------------------------------------------------------------
WITH order_totals AS (
    SELECT invoice,
           SUM(line_total) AS order_value
    FROM public.retail_clean
    WHERE line_type = 'sale'
    GROUP BY invoice
),
bands AS (
    SELECT invoice,
           order_value,
           NTILE(10) OVER (ORDER BY order_value) AS decile
    FROM order_totals
)
SELECT decile,
       COUNT(*)                 AS orders,
       ROUND(MIN(order_value))  AS min_value,
       ROUND(MAX(order_value))  AS max_value,
       ROUND(SUM(order_value))  AS revenue,
       ROUND(100.0 * SUM(order_value) / SUM(SUM(order_value)) OVER (), 1) AS pct_revenue
FROM bands
GROUP BY decile
ORDER BY decile;















-- =====================================================================
-- ONLINE RETAIL II  |  03 · DASHBOARD VIEWS  (for Power BI)
-- =====================================================================
-- Each view is small and already aggregated, so Power BI loads a few
-- rows per view instead of 1M invoice lines. Run this whole file once
-- (select all, F5) after Part 1 of the workbook. It is re-runnable.
--
-- Basis follows the workbook: net revenue = sales + cancellations;
-- gross = sales only. Same definitions and filters as the BQs.
--
-- Control values to compare after running (from the workbook results):
--   v_kpi_overview: net 19,013,836 | gross 20,476,260 | orders 40,077
--                   | customers 5,878 | cancelled 7.1% of gross
--   v_customer_bands: 4 rows, customers 1,623 / 2,094 / 1,187 / 974
--   v_order_deciles: 10 rows, revenue sums to about 20,476,260
--   v_country_net: UK net 16,144,363
-- =====================================================================

DROP VIEW IF EXISTS public.v_kpi_overview;
DROP VIEW IF EXISTS public.v_monthly_net;
DROP VIEW IF EXISTS public.v_country_net;
DROP VIEW IF EXISTS public.v_customer_bands;
DROP VIEW IF EXISTS public.v_order_deciles;
DROP VIEW IF EXISTS public.v_orders_by_weekday;
DROP VIEW IF EXISTS public.v_orders_by_hour;


-- ---------------------------------------------------------------------
-- KPI cards (overview): one row
-- customers = customers with at least one sale (guest rows excluded)
-- ---------------------------------------------------------------------
CREATE VIEW public.v_kpi_overview AS
SELECT ROUND(SUM(line_total))                                              AS net_revenue,
       ROUND(SUM(line_total) FILTER (WHERE line_type = 'sale'))            AS gross_revenue,
       ROUND(SUM(-line_total) FILTER (WHERE line_type = 'cancellation'))   AS cancelled_value,
       ROUND(100.0 * SUM(-line_total) FILTER (WHERE line_type = 'cancellation')
             / SUM(line_total) FILTER (WHERE line_type = 'sale'), 1)       AS pct_cancelled,
       COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale')           AS orders,
       COUNT(DISTINCT customer_id) FILTER (WHERE line_type = 'sale')       AS customers
FROM public.retail_clean
WHERE line_type IN ('sale', 'cancellation');


-- ---------------------------------------------------------------------
-- BQ03 · monthly net and gross revenue (December 2011 is incomplete and
--        excluded)
-- ---------------------------------------------------------------------
CREATE VIEW public.v_monthly_net AS
SELECT DATE_TRUNC('month', invoice_ts)::date                               AS month,
       EXTRACT(YEAR  FROM invoice_ts)::int                                 AS year,
       EXTRACT(MONTH FROM invoice_ts)::int                                 AS month_no,
       ROUND(SUM(line_total))                                              AS net_revenue,
       ROUND(SUM(line_total) FILTER (WHERE line_type = 'sale'))            AS gross_revenue,
       COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale')           AS orders
FROM public.retail_clean
WHERE line_type IN ('sale', 'cancellation')
  AND invoice_ts < DATE '2011-12-01'
GROUP BY 1, 2, 3;


-- ---------------------------------------------------------------------
-- BQ04 · net revenue by country
-- ---------------------------------------------------------------------
CREATE VIEW public.v_country_net AS
SELECT country,
       ROUND(SUM(line_total))                                              AS net_revenue,
       COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale')           AS orders,
       ROUND(SUM(line_total)
             / NULLIF(COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale'), 0)) AS net_revenue_per_order,
       ROUND(100.0 * SUM(line_total) / SUM(SUM(line_total)) OVER (), 1)    AS pct_of_net_revenue
FROM public.retail_clean
WHERE line_type IN ('sale', 'cancellation')
GROUP BY country;


-- ---------------------------------------------------------------------
-- BQ08 · customers and net revenue by number of orders
-- band_order is used to sort the bands correctly in the report
-- ---------------------------------------------------------------------
CREATE VIEW public.v_customer_bands AS
WITH customer AS (
    SELECT customer_id,
           COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale') AS orders,
           SUM(line_total)                                           AS net_revenue
    FROM public.retail_clean
    WHERE line_type IN ('sale', 'cancellation')
      AND customer_id IS NOT NULL
    GROUP BY customer_id
    HAVING COUNT(DISTINCT invoice) FILTER (WHERE line_type = 'sale') > 0
)
SELECT CASE WHEN orders = 1              THEN 1
            WHEN orders BETWEEN 2 AND 4  THEN 2
            WHEN orders BETWEEN 5 AND 9  THEN 3
            ELSE 4 END                                                  AS band_order,
       CASE WHEN orders = 1              THEN '1 order'
            WHEN orders BETWEEN 2 AND 4  THEN '2-4 orders'
            WHEN orders BETWEEN 5 AND 9  THEN '5-9 orders'
            ELSE '10+ orders' END                                       AS order_band,
       COUNT(*)                                                         AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS pct_customers,
       ROUND(SUM(net_revenue))                                          AS net_revenue,
       ROUND(100.0 * SUM(net_revenue) / SUM(SUM(net_revenue)) OVER (), 1) AS pct_revenue
FROM customer
GROUP BY 1, 2;


-- ---------------------------------------------------------------------
-- BQ10 · revenue by order-size decile (gross sales, one row per invoice)
-- ---------------------------------------------------------------------
CREATE VIEW public.v_order_deciles AS
WITH order_totals AS (
    SELECT invoice,
           SUM(line_total) AS order_value
    FROM public.retail_clean
    WHERE line_type = 'sale'
    GROUP BY invoice
),
bands AS (
    SELECT invoice,
           order_value,
           NTILE(10) OVER (ORDER BY order_value) AS decile
    FROM order_totals
)
SELECT decile,
       COUNT(*)                 AS orders,
       ROUND(MIN(order_value))  AS min_value,
       ROUND(MAX(order_value))  AS max_value,
       ROUND(SUM(order_value))  AS revenue,
       ROUND(100.0 * SUM(order_value) / SUM(SUM(order_value)) OVER (), 1) AS pct_revenue
FROM bands
GROUP BY decile;


-- ---------------------------------------------------------------------
-- BQ09 · orders by weekday (gross sales)
-- ---------------------------------------------------------------------
CREATE VIEW public.v_orders_by_weekday AS
SELECT EXTRACT(ISODOW FROM invoice_ts)::int AS day_no,
       TRIM(TO_CHAR(invoice_ts, 'Day'))     AS day_name,
       COUNT(DISTINCT invoice)              AS orders,
       ROUND(SUM(line_total))               AS revenue
FROM public.retail_clean
WHERE line_type = 'sale'
GROUP BY 1, 2;


-- ---------------------------------------------------------------------
-- BQ09b · orders by hour (gross sales)
-- ---------------------------------------------------------------------
CREATE VIEW public.v_orders_by_hour AS
SELECT EXTRACT(HOUR FROM invoice_ts)::int              AS hour_of_day,
       COUNT(DISTINCT invoice)                         AS orders,
       ROUND(SUM(line_total))                          AS revenue,
       ROUND(SUM(line_total) / COUNT(DISTINCT invoice)) AS revenue_per_order
FROM public.retail_clean
WHERE line_type = 'sale'
GROUP BY 1;


-- ---------------------------------------------------------------------
-- Quick check: row counts of the views (all should be > 0)
--   v_kpi_overview 1 | v_customer_bands 4 | v_order_deciles 10
--   v_orders_by_weekday 7 | v_orders_by_hour 15 | v_monthly_net 24
--   v_country_net 43
-- ---------------------------------------------------------------------
SELECT 'v_kpi_overview'      AS view_name, COUNT(*) AS row_count FROM public.v_kpi_overview
UNION ALL SELECT 'v_monthly_net',        COUNT(*) FROM public.v_monthly_net
UNION ALL SELECT 'v_country_net',        COUNT(*) FROM public.v_country_net
UNION ALL SELECT 'v_customer_bands',     COUNT(*) FROM public.v_customer_bands
UNION ALL SELECT 'v_order_deciles',      COUNT(*) FROM public.v_order_deciles
UNION ALL SELECT 'v_orders_by_weekday',  COUNT(*) FROM public.v_orders_by_weekday
UNION ALL SELECT 'v_orders_by_hour',     COUNT(*) FROM public.v_orders_by_hour;


SELECT * FROM v_kpi_overview;
SELECT * FROM v_monthly_net;
SELECT * FROM v_country_net
SELECT * FROM v_customer_bands
SELECT * FROM v_order_deciles
SELECT * FROM v_orders_by_weekday
SELECT * FROM v_orders_by_hour