-- =====================================================================
-- 01_ods.sql
-- ODS 层：原样导入三个原始 CSV，不做任何清洗
-- ODS layer: load the three raw CSVs as-is, with no cleaning
--
-- 路径相对于项目根目录，请在项目根目录运行 build_db.py
-- Paths are relative to the project root; run build_db.py from there
-- =====================================================================


-- ---------------------------------------------------------------------
-- 交易表：手动指定列类型
-- Transactions: column types set by hand
--   t_dat      → DATE，之后才能按周截断 / so it can be truncated to weeks
--   article_id → BIGINT，去掉前导 0，和商品表统一 / drops leading zeros so it matches the articles table
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE ods_transactions AS
SELECT *
FROM read_csv('data/raw/transactions_train.csv',
    header = true,
    columns = {
        't_dat': 'DATE',
        'customer_id': 'VARCHAR',
        'article_id': 'BIGINT',
        'price': 'DOUBLE',
        'sales_channel_id': 'TINYINT'
    });


-- ---------------------------------------------------------------------
-- 商品表：自动识别类型（article_id 会被识别为 VARCHAR，在 DWD 层转换）
-- Articles: types auto-detected (article_id comes in as VARCHAR; cast at DWD)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE ods_articles AS
SELECT * FROM read_csv_auto('data/raw/articles.csv', header = true);


-- ---------------------------------------------------------------------
-- 顾客表：自动识别类型
-- Customers: types auto-detected
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE ods_customers AS
SELECT * FROM read_csv_auto('data/raw/customers.csv', header = true);
