-- =====================================================================
-- 03_dws.sql
-- DWS 层：提前算好常用汇总，供分析和看板直接使用
-- DWS layer: pre-computed aggregates for analysis and dashboards
--
-- 口径说明见 docs/data_dictionary.md 第 7 节
-- Definitions are documented in docs/data_dictionary.md, section 7
-- =====================================================================


-- ---------------------------------------------------------------------
-- dws_week_article：一行 = 一周 × 一个商品（剔除不完整周）
-- dws_week_article: one row = one week × one article (partial weeks excluded)
-- 用途：爆款分析、价格弹性 / Used for best-seller analysis and price elasticity
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE dws_week_article AS
SELECT
    week_start,
    article_id,

    -- 销量 = 行数（含批量购买）/ Units = row count (bulk included)
    COUNT(*) AS units,

    -- 相对销售额，单位是价格点，不是货币 / Relative revenue in price-point units, not currency
    SUM(price_point) AS revenue,

    -- 按件加权的平均价格点 / Unit-weighted average price point
    AVG(price_point) AS avg_price_point,

    -- 去重人数：不能跨周或跨商品相加 / Distinct buyers: not additive across weeks or articles
    COUNT(DISTINCT customer_id) AS n_customers,

    -- 渠道 2 的销量（渠道含义未确认）/ Channel 2 units (channel meaning unconfirmed)
    COUNT(*) FILTER (WHERE sales_channel_id = 2) AS units_ch2,

    -- 剔除批量组合后的销量，用于顾客与爆款分析及敏感性分析
    -- Units excluding bulk groups, for customer / best-seller analysis and sensitivity checks
    COUNT(*) FILTER (WHERE NOT is_bulk) AS units_excl_bulk
FROM dwd_transactions
WHERE NOT is_partial_week
GROUP BY week_start, article_id;


-- ---------------------------------------------------------------------
-- dws_week_category：一行 = 一周 × 大类 × 小类（剔除不完整周）
-- dws_week_category: one row = one week × product group × product type
-- 从 DWD 而不是 dws_week_article 计算，因为品类级去重人数必须回到明细
-- Built from DWD, not dws_week_article, because category-level distinct
-- buyers must be computed from the detail table
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE dws_week_category AS
SELECT
    week_start,
    product_group_name,
    product_type_name,
    COUNT(*)                                     AS units,
    COUNT(*) FILTER (WHERE NOT is_bulk)          AS units_excl_bulk,
    COUNT(*) FILTER (WHERE sales_channel_id = 2) AS units_ch2,
    SUM(price_point)                             AS revenue,

    -- 动销 SKU 数：同一周内可跨小类相加（每个商品只属于一个小类），跨周不可
    -- Distinct articles sold: additive across types within a week, not across weeks
    COUNT(DISTINCT article_id)                   AS n_articles_sold,

    -- 去重人数：不可相加 / Distinct buyers: not additive
    COUNT(DISTINCT customer_id)                  AS n_customers
FROM dwd_transactions
WHERE NOT is_partial_week
GROUP BY week_start, product_group_name, product_type_name;


-- ---------------------------------------------------------------------
-- dws_articles：一行 = 一个卖出过的商品（商品生命周期）
-- dws_articles: one row = one article sold at least once (article lifecycle)
-- 使用全部数据（含不完整周），否则首次 / 最后出售日会算错
-- Uses all data including partial weeks; otherwise first / last sale dates shift
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE dws_articles AS
WITH life AS (
    SELECT
        article_id,
        -- 每个商品只有一个品类（函数依赖），放进 GROUP BY 不会拆组
        -- Each article has exactly one category (functional dependency), so these
        -- extra GROUP BY columns do not split groups
        product_group_name,
        product_type_name,

        -- 首次出售日作为上新日的代理 / First sale date as a proxy for launch date
        MIN(t_dat)                          AS first_sale_date,
        MIN(week_start)                     AS first_sale_week,
        MAX(t_dat)                          AS last_sale_date,
        COUNT(*)                            AS total_units,
        COUNT(*) FILTER (WHERE NOT is_bulk) AS total_units_excl_bulk
    FROM dwd_transactions
    GROUP BY article_id, product_group_name, product_type_name
),

last_full_week AS (
    -- 最后一个完整周（2020-09-14），从数据中计算而不是写死
    -- Last full week (2020-09-14), computed from the data rather than hard-coded
    SELECT MAX(week_start) AS week_start
    FROM dwd_transactions
    WHERE NOT is_partial_week
)

SELECT
    life.*,

    -- 左删失：2018-10-29 之前首次出售的多为数据开始前的老款（见数据字典 §7.3）
    -- Left censoring: articles first sold before 2018-10-29 are mostly older
    -- articles already on sale before the data starts (see §7.3)
    life.first_sale_date >= DATE '2018-10-29' AS is_launch_observed,

    -- 右删失：上新周 + 7 周不晚于最后一个完整周，才算观测满 8 周
    -- Right censoring: 8 full weeks are observed only if launch week + 7 weeks
    -- is no later than the last full week
    life.first_sale_week + INTERVAL 7 WEEK <= lfw.week_start AS has_full_8w
FROM life
CROSS JOIN last_full_week lfw;
