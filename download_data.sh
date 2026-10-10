#!/usr/bin/env bash
# 下载 H&M 原始数据到 data/raw/（只需运行一次）
# Download the raw H&M data into data/raw/ (run once)
# 前提 / Prerequisite: kaggle auth login，并在网页上接受比赛规则
set -e
cd "$(dirname "$0")"

COMP=h-and-m-personalized-fashion-recommendations
mkdir -p data/raw
for f in transactions_train.csv articles.csv customers.csv; do
    kaggle competitions download -c "$COMP" -f "$f" -p data/raw
done

cd data/raw
unzip -o '*.zip'
rm -f *.zip
ls -lh