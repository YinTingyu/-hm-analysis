"""
数据核对：建表后运行，检查各层之间的数字是否对得上。
Data checks: run after building to confirm the numbers reconcile across layers.

每条检查是一条 SQL，返回 (实际值, 期望值) 两列；相等即通过。
Each check is one SQL query returning (actual, expected); equal means pass.
这些都是「不变量」，不依赖具体数据，所以数据更新后也能直接重跑。
They are invariants that do not depend on specific numbers, so they still
apply after the data changes.

用法 / Usage:
    python checks.py
"""

import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent
DB_PATH = ROOT / "data" / "hm.duckdb"


# (说明 / description, SQL 返回 actual, expected)
CHECKS = [
    # ---------------- DWD：清洗不应改变行数 / cleaning must not change row counts
    (
        "dwd_customers 行数 = ODS / row count equals ODS",
        "SELECT (SELECT COUNT(*) FROM dwd_customers), (SELECT COUNT(*) FROM ods_customers)",
    ),
    (
        "dwd_articles 行数 = ODS / row count equals ODS",
        "SELECT (SELECT COUNT(*) FROM dwd_articles), (SELECT COUNT(*) FROM ods_articles)",
    ),
    (
        "dwd_transactions 行数 = ODS（关联没有增减行）/ row count equals ODS (joins added or dropped nothing)",
        "SELECT (SELECT COUNT(*) FROM dwd_transactions), (SELECT COUNT(*) FROM ods_transactions)",
    ),
    (
        "fashion_news_frequency 已无 'None' 写法 / no 'None' spelling left",
        "SELECT COUNT(*) FILTER (WHERE fashion_news_frequency = 'None'), 0 FROM dwd_customers",
    ),
    (
        "交易都关联到商品属性 / every transaction has article attributes",
        "SELECT COUNT(*) FILTER (WHERE product_group_name IS NULL), 0 FROM dwd_transactions",
    ),
    (
        "交易都关联到顾客年龄组 / every transaction has a customer age group",
        "SELECT COUNT(*) FILTER (WHERE age_group IS NULL), 0 FROM dwd_transactions",
    ),
    (
        # 用 GROUP BY 的方法再算一次批量行数，和窗口函数的结果对比
        # Recount bulk rows with GROUP BY and compare with the window-function flag
        "is_bulk 行数：窗口函数 = GROUP BY 方法 / bulk rows: window function = GROUP BY method",
        """
        SELECT
            (SELECT COUNT(*) FROM dwd_transactions WHERE is_bulk),
            (SELECT SUM(n) FROM (
                SELECT COUNT(*) AS n FROM ods_transactions
                GROUP BY t_dat, customer_id, article_id
                HAVING COUNT(*) > 5))
        """,
    ),
    (
        # 不完整周只能是第一周和最后一周 / partial weeks may only be the first and last week
        "不完整周只在首尾 / partial weeks are only at the edges",
        """
        WITH p AS (SELECT DISTINCT week_start FROM dwd_transactions WHERE is_partial_week),
             edges AS (SELECT MIN(week_start) AS w FROM dwd_transactions
                       UNION SELECT MAX(week_start) FROM dwd_transactions)
        SELECT COUNT(*) FILTER (WHERE week_start NOT IN (SELECT w FROM edges)), 0 FROM p
        """,
    ),
    # ---------------- DWS：汇总后总量不变 / totals survive aggregation
    (
        "dws_week_article SUM(units) = DWD 完整周行数 / equals DWD rows in full weeks",
        """
        SELECT (SELECT SUM(units) FROM dws_week_article),
               (SELECT COUNT(*) FROM dwd_transactions WHERE NOT is_partial_week)
        """,
    ),
    (
        "dws_week_article SUM(units_excl_bulk) = DWD 完整周非批量行数 / equals non-bulk DWD rows in full weeks",
        """
        SELECT (SELECT SUM(units_excl_bulk) FROM dws_week_article),
               (SELECT COUNT(*) FROM dwd_transactions WHERE NOT is_partial_week AND NOT is_bulk)
        """,
    ),
    (
        "dws_week_category SUM(units) = DWD 完整周行数 / equals DWD rows in full weeks",
        """
        SELECT (SELECT SUM(units) FROM dws_week_category),
               (SELECT COUNT(*) FROM dwd_transactions WHERE NOT is_partial_week)
        """,
    ),
    (
        # 每个商品只有一个品类：行数应等于去重商品数
        # One category per article: row count must equal distinct articles
        "dws_articles 一个商品一行 / one row per article",
        "SELECT COUNT(*), COUNT(DISTINCT article_id) FROM dws_articles",
    ),
    (
        "dws_articles 行数 = 卖出过的商品数 / equals articles sold",
        "SELECT (SELECT COUNT(*) FROM dws_articles), (SELECT COUNT(DISTINCT article_id) FROM dwd_transactions)",
    ),
    (
        "dws_articles SUM(total_units) = 全部交易行数 / equals all transaction rows",
        "SELECT (SELECT SUM(total_units) FROM dws_articles), (SELECT COUNT(*) FROM dwd_transactions)",
    ),
    (
        # 上新早的商品一定观测满 8 周，所以两个标记不可能同时为 FALSE
        # Early launches always have 8 full weeks, so both flags cannot be FALSE
        "不存在 FALSE/FALSE 组合 / no FALSE/FALSE flag combination",
        "SELECT COUNT(*) FILTER (WHERE NOT is_launch_observed AND NOT has_full_8w), 0 FROM dws_articles",
    ),
]


def main() -> int:
    if not DB_PATH.exists():
        print(f"找不到数据库 / Database not found: {DB_PATH}\n先运行 / Run first: python build_db.py")
        return 1

    # 只读打开，避免误改数据 / Open read-only so checks cannot change data
    con = duckdb.connect(str(DB_PATH), read_only=True)

    n_fail = 0
    for description, sql in CHECKS:
        actual, expected = con.sql(sql).fetchone()
        ok = actual == expected
        n_fail += not ok
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {description}")
        print(f"        实际 actual = {actual:,}   期望 expected = {expected:,}")

    con.close()
    print(f"\n{len(CHECKS) - n_fail}/{len(CHECKS)} 通过 / passed")
    # 有失败时返回非 0，方便以后接入自动化 / Non-zero exit on failure, ready for automation
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
