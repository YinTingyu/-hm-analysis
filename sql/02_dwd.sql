-- =====================================================================
-- 02_dwd.sql
-- DWD 层：把 ODS 清洗成可直接分析的明细表；所有清洗规则只在这里定义一次
-- DWD layer: clean ODS into analysis-ready detail tables; every cleaning
-- rule is defined here once, and downstream tables use the flags
--
-- 规则说明见 docs/data_dictionary.md 第 4、6 节
-- Rules are documented in docs/data_dictionary.md, sections 4 and 6
-- =====================================================================


-- ---------------------------------------------------------------------
-- dwd_customers：一行 = 一个顾客
-- dwd_customers: one row = one customer
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE dwd_customers AS
SELECT
    customer_id,

    -- FN / Active 只有 1.0 和 NULL；NULL 视为 0（否）
    -- FN / Active are 1.0 or NULL only; NULL is treated as 0 (no)
    CAST(COALESCE(FN, 0) AS INTEGER)     AS is_fn,
    CAST(COALESCE(Active, 0) AS INTEGER) AS is_active,

    -- 缺失的会员状态单列为 UNKNOWN
    -- Missing club status becomes its own UNKNOWN group
    COALESCE(club_member_status, 'UNKNOWN') AS club_member_status,

    -- 统一 None / NONE 等不同写法，缺失值为 UNKNOWN
    -- Normalise spellings such as None / NONE; missing values become UNKNOWN
    COALESCE(
        CASE WHEN UPPER(TRIM(fashion_news_frequency)) = 'NONE' THEN 'NONE'
             ELSE fashion_news_frequency END,
        'UNKNOWN'
    ) AS fashion_news_frequency,

    age,

    -- 年龄分组：age 为 NULL 时所有比较都不是 TRUE，因此落入 ELSE
    -- Age groups: when age is NULL no comparison is TRUE, so it falls to ELSE
    CASE
        WHEN age < 25 THEN '<25'
        WHEN age < 35 THEN '25-34'
        WHEN age < 45 THEN '35-44'
        WHEN age < 55 THEN '45-54'
        WHEN age >= 55 THEN '55+'
        ELSE 'UNKNOWN'
    END AS age_group
FROM ods_customers;


-- ---------------------------------------------------------------------
-- dwd_articles：一行 = 一个商品（款式 + 颜色）
-- dwd_articles: one row = one article (style + colour)
-- 保留全部列，只把 article_id 转成 BIGINT，便于和交易表关联
-- Keep every column; only cast article_id to BIGINT to join with transactions
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE dwd_articles AS
SELECT * REPLACE (CAST(article_id AS BIGINT) AS article_id)
FROM ods_articles;


-- ---------------------------------------------------------------------
-- dwd_transactions：一行 = 一件商品的一次购买（粒度与 ODS 相同）
-- dwd_transactions: one row = one unit purchased (same grain as ODS)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE dwd_transactions AS
WITH t AS (
    -- 逐行加工 / Row-level derived columns
    SELECT
        t_dat,

        -- 所在周的周一 / Monday of the week
        CAST(DATE_TRUNC('week', t_dat) AS DATE) AS week_start,

        customer_id,
        article_id,
        price,

        -- 价格点：price × 59 呈现 x.x99 结尾的离散值；四舍五入消除浮点误差
        -- Price point: price × 59 gives discrete .x99 values; rounding removes float noise
        ROUND(price * 59, 3) AS price_point,

        sales_channel_id,

        -- 窗口函数：同日同顾客同商品共有几行（保留所有行，不改变粒度）
        -- Window function: rows per day–customer–article (keeps every row; grain unchanged)
        COUNT(*) OVER (PARTITION BY t_dat, customer_id, article_id) AS n_same_day
    FROM ods_transactions
),

week_days AS (
    -- 每周有交易的天数，用来识别不完整的周
    -- Days with transactions per week, used to detect partial weeks
    SELECT week_start, COUNT(DISTINCT t_dat) AS n_days
    FROM t
    GROUP BY week_start
)

SELECT
    t.*,

    -- 批量购买：同日同顾客同商品超过 5 件（见数据字典 §4.3）
    -- Bulk purchase: more than 5 units of one article by one customer on one day (see §4.3)
    t.n_same_day > 5 AS is_bulk,

    -- 不完整周：该周有交易的天数少于 7
    -- Partial week: fewer than 7 days with transactions
    w.n_days < 7 AS is_partial_week,

    -- 常用商品属性；其余属性需要时按 article_id 关联 dwd_articles
    -- Frequently used article attributes; join dwd_articles by article_id for the rest
    a.product_group_name,
    a.product_type_name,
    a.garment_group_name,
    a.department_name,
    a.section_name,
    a.index_group_name,
    a.colour_group_name,
    a.perceived_colour_master_name,

    -- 顾客年龄组 / Customer age group
    c.age_group
FROM t
JOIN week_days w USING (week_start)
-- LEFT JOIN：即使匹配不上也保留交易，缺失可在检查中发现
-- LEFT JOIN keeps transactions even without a match, so gaps show up in checks
LEFT JOIN dwd_articles  a USING (article_id)
LEFT JOIN dwd_customers c USING (customer_id);
