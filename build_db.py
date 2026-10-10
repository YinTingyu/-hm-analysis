"""
从原始 CSV 一键重建 DuckDB 数据库：按文件名顺序执行 sql/ 下的脚本。
Rebuild the DuckDB database from the raw CSVs by running the scripts in
sql/ in file-name order.

用法 / Usage (在项目根目录或任意位置 / from anywhere):
    python build_db.py                 # 全部重建 / rebuild everything
    python build_db.py --skip-ods      # 跳过 ODS 导入（CSV 没变时更快）
                                       # skip ODS load (faster when CSVs are unchanged)
    python build_db.py --memory-limit 6GB

注意 / Note:
    运行前先关掉正在连接 hm.duckdb 的 notebook kernel，否则会被锁住。
    Shut down any notebook kernel connected to hm.duckdb first, or the file is locked.
"""

import argparse
import os
import time
from pathlib import Path

import duckdb

# 项目根目录 = 本脚本所在文件夹；SQL 里的相对路径都以它为起点
# Project root = this script's folder; relative paths in the SQL start here
ROOT = Path(__file__).resolve().parent
SQL_DIR = ROOT / "sql"
DB_PATH = ROOT / "data" / "hm.duckdb"


def parse_args():
    parser = argparse.ArgumentParser(description="Build the H&M DuckDB database")
    parser.add_argument(
        "--skip-ods",
        action="store_true",
        help="跳过 01_ods.sql / skip 01_ods.sql (reuse existing ODS tables)",
    )
    parser.add_argument(
        "--memory-limit",
        default=None,
        help="DuckDB 内存上限，如 6GB / DuckDB memory limit, e.g. 6GB",
    )
    return parser.parse_args()


def list_sql_files(skip_ods: bool) -> list[Path]:
    """按文件名排序，所以文件名前缀 01_、02_ 决定执行顺序。
    Sorted by name, so the 01_, 02_ prefixes set the run order."""
    files = sorted(SQL_DIR.glob("*.sql"))
    if skip_ods:
        files = [f for f in files if not f.name.startswith("01_")]
    return files


def print_table_sizes(con: duckdb.DuckDBPyConnection) -> None:
    """打印每张表的行数，方便快速核对。/ Print row counts for a quick sanity check."""
    tables = [row[0] for row in con.sql("SHOW TABLES").fetchall()]
    print("\n表 / Table                     行数 / Rows")
    for name in sorted(tables):
        n = con.sql(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
        print(f"  {name:<28}{n:>14,}")


def main():
    args = parse_args()

    # 切换到项目根目录，保证 SQL 里的 'data/raw/...' 能找到文件
    # Move to the project root so 'data/raw/...' in the SQL resolves
    os.chdir(ROOT)
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect(str(DB_PATH))
    if args.memory_limit:
        con.execute(f"SET memory_limit = '{args.memory_limit}'")

    for sql_file in list_sql_files(args.skip_ods):
        start = time.time()
        print(f"运行 / Running {sql_file.name} ...", end=" ", flush=True)
        con.execute(sql_file.read_text(encoding="utf-8"))
        print(f"{time.time() - start:.1f}s")

    print_table_sizes(con)
    con.close()
    print("\n完成 / Done. 下一步运行 / Next run: python checks.py")


if __name__ == "__main__":
    main()
